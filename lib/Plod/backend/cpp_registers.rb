# frozen_string_literal: true

module Plod
  module Backend
    class Cpp
      private

      def register_value(reg, index = nil)
        value = index ? "#{reg.name}[#{index}]" : reg.name.to_s
        value = "this->#{value}" if @checkpoint_emitting || @packet_emitting
        bank_backend? ? "#{value}.get()" : value
      end

      def indexed_expr(container, index)
        reg = if container.kind == :self && container.subject == :register
                @register
              elsif container.kind == :var
                @device.registers.find { |r| r.name == container.name }
              end
        return register_value(reg, expr(index)) if reg

        "#{expr(container)}[#{expr(index)}]"
      end

      def emit_collection_helpers
        line('#ifndef PROTEA_PLOD_COLLECTION_HELPERS')
        line('#define PROTEA_PLOD_COLLECTION_HELPERS')
        line('namespace protea {')
        indent do
          line('template <typename M> auto firstKey(const M& m) { return m.begin()->first; }')
          line('template <typename M> auto firstValue(const M& m) { return m.begin()->second; }')
          line('template <typename M> void eraseFirst(M& m) { m.erase(m.begin()); }')
          line('template <typename C> uint32_t loadWord(C& cp, const std::string& key) {')
          indent { line('uint32_t value; paramIn(cp, key, value); return value;') }
          line('}')
          line('template <typename C> uint64_t loadTick(C& cp, const std::string& key) {')
          indent { line('uint64_t value; paramIn(cp, key, value); return value;') }
          line('}')
          line('template <typename P> bool isAtomicSwap(P* pkt) {')
          indent { line('return pkt->isAtomicOp() && pkt->cmd == gem5::MemCmd::SwapReq;') }
          line('}')
          line('template <typename P> void applyAtomic(P* pkt) {')
          indent { line('(*(pkt->getAtomicOp()))(pkt->template getPtr<uint8_t>());') }
          line('}')
        end
        line('}')
        line('#endif')
        line('')
      end

      # This mode is for strict word transports. Device-defined packet methods
      # perform width checks and forwarding before invoking these dispatchers.
      def emit_word_dispatch
        @device.registers.each do |reg|
          raise Plod::Error, 'word backend requires scalar 32-bit registers' if reg.banked? || reg.size != 4
        end
        line('uint32_t readRegister(Addr offset) {')
        indent do
          dispatchable(:read).each do |reg|
            condition = "offset == #{reg.offset}"
            condition += " && (#{expr(reg.enable_if)})" if reg.enable_if
            line("if (#{condition}) return #{reg.name}_read();")
          end
          line('return readUnknown(offset);')
        end
        line('}')
        line('void writeRegister(Addr offset, uint32_t data) {')
        indent do
          dispatchable(:write).each do |reg|
            condition = "offset == #{reg.offset}"
            condition += " && (#{expr(reg.enable_if)})" if reg.enable_if
            line("if (#{condition}) { #{reg.name}_write(data); return; }")
          end
          line('writeUnknown(offset, data);')
        end
        line('}')
      end

      # Use gem5's bank for endian conversion, partial accesses and operations
      # spanning several registers. Callbacks invoke the PLOD register methods.
      def emit_register_bank
        line('RegisterBankLE _registerBank;')
        line('std::vector<std::unique_ptr<RegisterBankLE::RegisterRaz>> _registerGaps;')
        line('void initRegisters() {')
        indent do
          line('struct Entry { Addr offset; RegisterBankLE::RegisterBase* reg; };')
          line('std::vector<Entry> entries;')
          @device.registers.each do |reg|
            raise Plod::Error, 'gem5_bank does not support overlapping EnableIf registers' if reg.enable_if

            emit_bank_register(reg)
          end
          line('std::stable_sort(entries.begin(), entries.end(), [](auto a, auto b) { return a.offset < b.offset; });')
          line('Addr next = 0;')
          line('for (auto entry : entries) {')
          indent do
            line('panic_if(entry.offset < next || entry.offset > pioSize || ' \
                 'entry.reg->size() > pioSize - entry.offset, "Invalid register layout");')
            line('if (entry.offset > next) {')
            indent do
              line('_registerGaps.push_back(std::make_unique<RegisterBankLE::RegisterRaz>(' \
                   '"reserved" + std::to_string(_registerGaps.size()), entry.offset - next));')
              line('_registerBank.addRegister(*_registerGaps.back());')
            end
            line('}')
            line('_registerBank.addRegister(*entry.reg);')
            line('next = entry.offset + entry.reg->size();')
          end
          line('}')
          line('if (next < pioSize) {')
          indent do
            line('_registerGaps.push_back(std::make_unique<RegisterBankLE::RegisterRaz>(' \
                 '"reserved" + std::to_string(_registerGaps.size()), pioSize - next));')
            line('_registerBank.addRegister(*_registerGaps.back());')
          end
          line('}')
        end
        line('}')
        line('void readRegisters(PacketPtr pkt) {')
        indent { line('_registerBank.read(pkt->getAddr(), pkt->getPtr<void>(), pkt->getSize());') }
        line('}')
        line('void writeRegisters(PacketPtr pkt) {')
        indent { line('_registerBank.write(pkt->getAddr(), pkt->getPtr<void>(), pkt->getSize());') }
        line('}')
      end

      def emit_bank_register(reg)
        dims = reg.layout || (reg.seqn ? [[IR::Const.new(value: reg.seqn), IR::Const.new(value: reg.size)]] : [])
        dims.each_with_index do |(count, stride), i|
          line("const int64_t #{reg.name}_count#{i} = #{expr(count)};")
          line("panic_if(#{reg.name}_count#{i} < 0 || #{expr(stride)} < #{reg.size}, " \
               "\"Invalid layout for #{reg.name}\");")
        end
        product = dims.each_index.map { |i| "#{reg.name}_count#{i}" }.join(' * ')
        line("#{reg.name}.reserve(#{product});") if reg.banked?
        line('{')
        indent do
          line('uint64_t cid = 0;') if reg.banked?
          emit_dimensions(reg, dims, 0) do |indices|
            if reg.banked?
              suffix = indices.map { |idx| " + std::to_string(#{idx})" }.join(' + "_"')
              line("#{reg.name}.emplace_back(\"#{reg.name}\"#{suffix}, 0);")
              storage = "#{reg.name}.back()"
            else
              storage = reg.name.to_s
            end
            line("auto& reg = #{storage};")
            cid = reg.banked? ? ', cid' : ''
            args = reg.banked? ? 'cid' : ''
            line("reg.reader([this#{cid}](auto&) { return #{reg.name}_read(#{args}); });") unless reg.access == :wo
            if reg.access == :ro
              line('reg.readonly();')
            else
              line("reg.writer([this#{cid}](auto&, const auto& data) { #{reg.name}_write(data#{cid}); });")
            end
            offset = dims.each_with_index.map { |(_, stride), i| " + #{indices[i]} * #{expr(stride)}" }.join
            line("entries.push_back({static_cast<Addr>(#{reg.offset}#{offset}), &reg});")
            line('++cid;') if reg.banked?
          end
        end
        line('}')
        return unless reg.window

        extent = dims.empty? ? reg.size.to_s : "#{reg.name}_count0 * #{expr(dims[0][1])}"
        emit_padding("#{reg.offset} + #{extent}", "#{reg.window} - #{extent}")
      end

      def emit_padding(offset, size)
        line('{')
        indent do
          line("const Addr offset = #{offset};")
          line("const int64_t bytes = #{size};")
          line('panic_if(bytes < 0, "Register window overflows");')
          line('if (bytes > 0) {') unless @target.preserve_zero_padding
          indent do
            line('_registerGaps.push_back(std::make_unique<RegisterBankLE::RegisterRaz>(' \
                 '"padding" + std::to_string(_registerGaps.size()), bytes));')
            line('entries.push_back({offset, _registerGaps.back().get()});')
          end
          line('}') unless @target.preserve_zero_padding
        end
        line('}')
      end

      def emit_dimensions(reg, dims, depth, indices = [], &)
        return yield(indices) if depth == dims.size

        idx = "i#{depth}"
        line("for (int64_t #{idx} = 0; #{idx} < #{reg.name}_count#{depth}; ++#{idx}) {")
        indent do
          emit_dimensions(reg, dims, depth + 1, indices + [idx], &)
          if depth < dims.size - 1
            prefix = (indices + [idx]).each_with_index.map { |index, i| " + #{index} * #{expr(dims[i][1])}" }.join
            extent = "#{reg.name}_count#{depth + 1} * #{expr(dims[depth + 1][1])}"
            emit_padding("#{reg.offset}#{prefix} + #{extent}", "#{expr(dims[depth][1])} - #{extent}")
          end
        end
        line('}')
      end
    end
  end
end
