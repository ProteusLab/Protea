# frozen_string_literal: true

require_relative '../ir'
require_relative '../types'
require_relative 'target'

module Plod
  module Backend
    class Cpp
      BINOPS = {
        add: '+', sub: '-', mul: '*', div: '/', rem: '%',
        or: '|', and: '&', xor: '^', shl: '<<', shr: '>>',
        eq: '==', ne: '!=', lt: '<', le: '<=', gt: '>', ge: '>='
      }.freeze

      def self.generate(program, device, target)
        new(program, device, target).generate
      end

      def initialize(program, device, target)
        @program = program
        @device = device.is_a?(IR::DeviceDecl) ? device : program.devices.find { |d| d.name == device.to_sym }
        raise Plod::Error, "device '#{device}' not found in program" if @device.nil?

        @target = target
        @register = nil
        @out = []
        @indent = 0
      end

      def generate
        unless @target.supports_device?(@device.name)
          raise Plod::Error, "target does not support device #{@device.name}"
        end

        if @target.register_backend == 'custom' && !@target.packet &&
           (!custom_method?(:read) || !custom_method?(:write))
          raise Plod::Error, 'custom backend requires device-defined read and write packet methods'
        end

        validate_packet_policy if @target.packet

        if !@target.packet && @device.registers.any?(&:address)
          raise Plod::Error, 'absolute register Address requires a packet policy'
        end

        preamble
        line("namespace #{@target.namespace} {")
        @target.declarations.lines.each { |l| line(l.chomp) }
        line('')
        @device.fields.map(&:type).uniq.each { |t| emit_type_structs(t) }
        device_class
        line('}')
        "#{@out.join("\n")}\n"
      end

      private

      def line(text = '')
        @out << (text.empty? && @target.register_backend != 'legacy' ? '' : ('    ' * @indent) + text)
      end

      def indent
        @indent += 1
        yield
        @indent -= 1
      end

      def bank_backend? = @target.register_backend == 'gem5_bank'

      def custom_method?(name)
        @device.methods.any? { |m| m.name == name && !m.abstract }
      end

      def emit_type_structs(type)
        case type
        when Types::Named then emit_struct(type) if struct_type?(type)
        when Types::Array, Types::Vector then emit_type_structs(type.elem)
        when Types::Map
          emit_type_structs(type.key)
          emit_type_structs(type.elem)
        end
      end

      def struct_type?(type)
        type.is_a?(Types::Named) && concrete_struct(type.id)
      end

      def concrete_struct(name)
        @program.components.find { |c| c.name == name.to_sym && !c.abstract }
      end

      def env_name(name)
        @target.env_rewrite(name) || name.to_s
      end

      def cpp_type(type)
        case type
        when Types::Int then 'int'
        when Types::Bool then 'bool'
        when Types::Str then 'std::string'
        when Types::Auto then 'auto'
        when Types::Bits, Types::Field then int_type(type.size)
        when Types::Vector then "std::vector<#{cpp_type(type.elem)}>"
        when Types::Map then "std::map<#{cpp_type(type.key)}, #{cpp_type(type.elem)}>"
        when Types::Array then "std::array<#{cpp_type(type.elem)}, #{type.size}>"
        when Types::Ptr then "#{deref_cpp_name(type.stored)}*"
        when Types::Ref then "#{deref_cpp_name(type.stored)}&"
        when Types::Named then @target.env_rewrite(type.name) || type.name
        else
          raise Plod::Error, "cannot map type '#{type.name}' to C++"
        end
      end

      def deref_cpp_name(stored)
        cpp_type(stored)
      end

      def int_type(bits)
        return 'bool' if bits == 1

        return 'uint8_t' if bits <= 8
        return 'uint16_t' if bits <= 16
        return 'uint32_t' if bits <= 32

        'uint64_t'
      end

      def preamble
        @program.notice&.lines&.each { |l| line(l.chomp) }
        line('#pragma once')
        line('')
        @target.includes.each do |inc|
          line(inc.start_with?('<') ? "#include #{inc}" : "#include \"#{inc}\"")
        end
        line('')
        line('namespace protea {')
        indent do
          line('#ifndef PROTEA_PLOD_BIT_HELPERS')
          line('#define PROTEA_PLOD_BIT_HELPERS')
          line('template <typename BVTD, typename BVTS>')
          line('void _insert(BVTD& dest, uint32_t lsb, uint32_t size, BVTS src) {')
          indent do
            line('BVTD cleaner = ~((((BVTD)1 << size) - 1) << lsb);')
            line('BVTD data = ((BVTD)src & (((BVTD)1 << size) - 1)) << lsb;')
            line('dest &= cleaner;')
            line('dest |= data;')
          end
          line('}')
          line('')
          line('template <typename BVT>')
          line('BVT _extract(BVT op, uint32_t lsb, uint32_t size) {')
          indent do
            line('return (op >> lsb) & (((BVT)1 << size) - 1);')
          end
          line('}')
        end
        line('#endif')
        line('}')
        line('')
        emit_collection_helpers if @target.register_backend != 'legacy'
      end

      def emit_struct(type)
        component = concrete_struct(type.id)
        return if @emitted_structs&.include?(component.name)

        @emitted_structs ||= []
        @emitted_structs << component.name

        component.fields.each { |f| emit_type_structs(f.type) }
        line("struct #{component.name} {")
        indent do
          component.fields.each { |f| line("#{cpp_type(f.type)} #{f.name};") }
          init = component.methods.find { |m| m.name == :init }
          line("#{component.name}() {") if init
          if init
            indent { init.body.each { |s| stmt(s) } }
            line('}')
          end
          component.methods.each do |m|
            next if m.name == :init

            ret = m.ret_type.nil? ? 'void' : cpp_type(m.ret_type)
            args = m.args.map { |n, t| "#{cpp_type(t)} #{n}" }.join(', ')
            line('')
            line("#{ret} #{m.name}(#{args})#{' const' if m.const} {")
            indent { m.body.each { |s| stmt(s) } }
            line('}')
          end
        end
        line('};')
        line('')
      end

      def device_class
        @target.forward_decls.each { |decl| line(decl) }
        line('')
        line("class #{@device.name} : public #{@target.base} {")
        indent do
          device_members
          line('')
          line('public:')
          line('')
          device_public
        end
        line('};')
        line('')
      end

      def device_members
        @device.enums.each do |e|
          line("enum #{e.name} {")
          # rubocop:disable Style/HashEachMethods -- EnumDecl#values is a DTO member (Array), not Hash#values
          indent { e.values.each { |k, v| line("#{k} = #{v},") } }
          # rubocop:enable Style/HashEachMethods
          line('};')
          line('')
        end

        @device.consts.each do |c|
          line("#{cpp_type(c.type)} #{c.name} = #{const_value(c)};")
        end
        line('') unless @device.consts.empty?

        @device.lambdas.each do |l|
          sig = l.args.map { |_n, t| cpp_type(t) }.join(', ')
          params = l.args.map { |n, t| "#{cpp_type(t)} #{n}" }.join(', ')
          line("std::function<void(#{sig})> #{l.name} = [this](#{params}) {")
          indent { l.body.each { |s| stmt(s) } }
          line('};')
        end
        line('') unless @device.lambdas.empty?

        @device.fields.each do |f|
          next if @target.inherited_fields.include?(f.name)

          line(field_decl(f))
        end
        line('') unless @device.fields.empty?

        @device.registers.each do |r|
          line(register_storage(r))
        end
        line('') unless @device.registers.empty?

        @device.registers.each { |r| register_methods(r) }
        emit_register_bank if bank_backend?
        emit_word_dispatch if @target.register_backend == 'word' && !@target.packet
      end

      def const_value(c)
        c.value.is_a?(String) ? "\"#{c.value}\"" : c.value.to_s
      end

      def field_decl(f)
        return "#{cpp_type(f.type)} #{f.name};" if f.abstract || f.init_args.empty?

        if f.type.is_a?(Types::Auto)
          lambda_init = f.init_args.find { |a| a.is_a?(IR::LambdaDecl) }
          if f.init_args.size == 1 && lambda_init
            sig = lambda_init.args.map { |_n, t| cpp_type(t) }.join(', ')
            "std::function<void(#{sig})> #{f.name} = #{lambda_init.name};"
          else
            "auto #{f.name} = #{init_args(f)};"
          end
        else
          "#{cpp_type(f.type)} #{f.name} = #{cpp_type(f.type)}(#{init_args(f)});"
        end
      end

      def init_args(f)
        f.init_args.map do |a|
          if a.is_a?(IR::LambdaDecl)
            a.name.to_s
          elsif a.is_a?(String)
            "\"#{a}\""
          else
            a.to_s
          end
        end.join(', ')
      end

      def register_storage(reg)
        if bank_backend?
          type = "RegisterBankLE::Register<#{int_type(reg.size * 8)}>"
          return "std::vector<#{type}> #{reg.name};" if reg.banked?

          return "#{type} #{reg.name}{\"#{reg.name}\", 0};"
        end
        raise Plod::Error, 'runtime Layout requires the gem5_bank register backend' if reg.layout

        if reg.banked?
          "std::array<#{int_type(reg.size * 8)}, #{reg.seqn}> #{reg.name};"
        else
          "#{int_type(reg.size * 8)} #{reg.name} = 0;"
        end
      end

      def register_methods(reg)
        @register = reg
        reg.methods.each do |m|
          line('')
          register_method(reg, m)
        end

        unless reg.methods.any? { |m| m.name == :read }
          line('')
          if reg.banked?
            line("#{int_type(reg.size * 8)} #{reg.name}_read(uint64_t cid) { return #{register_value(reg, 'cid')}; }")
          else
            line("#{int_type(reg.size * 8)} #{reg.name}_read() { return #{register_value(reg)}; }")
          end
        end

        return if reg.methods.any? { |m| m.name == :write }

        line('')
        if reg.banked?
          value = register_value(reg, 'cid')
          line("void #{reg.name}_write(#{int_type(reg.size * 8)} data, uint64_t cid) { #{value} = data; }")
        else
          line("void #{reg.name}_write(#{int_type(reg.size * 8)} data) { #{register_value(reg)} = data; }")
        end
      end

      def register_method(reg, m)
        ret = m.ret_type.nil? ? 'void' : cpp_type(m.ret_type)
        args = m.args.map { |n, t| "#{cpp_type(t)} #{n}" }
        args << 'uint64_t cid' if reg.banked?
        line("#{ret} #{reg.name}_#{m.name}(#{args.join(', ')}) {")
        indent { m.body.each { |s| stmt(s) } }
        line('}')
      end

      def device_public
        if @target.register_backend != 'legacy'
          line("using Params = #{@target.params_type || "#{@device.name}Params"};")
        end

        @target.public_declarations.lines.each { |l| line(l.chomp) }

        @device.methods.reject(&:abstract).each do |m|
          ret = m.ret_type.nil? ? 'void' : cpp_type(m.ret_type)
          args = m.args.map { |n, t| "#{cpp_type(t)} #{n}" }.join(', ')
          line("#{ret} #{m.name}(#{args})#{' const' if m.const} {")
          indent { m.body.each { |s| stmt(s) } }
          line('}')
          line('')
        end

        emit_ctor
        emit_read
        emit_write
        emit_epilogue
      end

      def emit_ctor
        ctor = @device.ctor
        base_init = "#{@target.base}(#{@target.ctor_base_args})"
        init_list = ctor ? ctor.inits.map { |i| "#{i.field}(#{i.args.map { |a| expr(a) }.join(', ')})" } : []
        init_list.push('_registerBank(params.name, pioAddr)') if bank_backend?
        full_init = ([base_init] + init_list).join(', ')
        line("#{@device.name}(const #{@target.params_type || "#{@device.name}Params"} &params)")
        line("    : #{full_init} {")
        indent { ctor.body.each { |s| stmt(s) } } if ctor&.body && !ctor.body.empty?
        line('}')
        line('')
      end

      def dispatchable(access)
        excluded = access == :read ? :wo : :ro
        @device.registers.reject { |r| r.access == excluded }
      end

      def emit_read
        return emit_policy_packet(:read) if @target.packet
        return if custom_method?(:read)

        line('Tick read(PacketPtr pkt) override {')
        indent do
          line('uint64_t daddr = pkt->getAddr() - pioAddr;')
          line('uint8_t* data_ptr = pkt->getPtr<uint8_t>();')
          line('')
          if bank_backend?
            line('readRegisters(pkt);')
          else
            dispatchable(:read).each { |r| emit_dispatch_case(r, :read) }
          end
          line('')
          line('bool is_atomic = pkt->isAtomicOp() && pkt->cmd == MemCmd::SwapReq;')
          line('')
          line('if (is_atomic) {')
          indent do
            line('(*(pkt->getAtomicOp()))(pkt->getPtr<uint8_t>());')
            line('return write(pkt);')
          end
          line('} else {')
          indent do
            line('pkt->makeResponse();')
            line('return pioDelay;')
          end
          line('}')
        end
        line('}')
        line('')
      end

      def emit_write
        return emit_policy_packet(:write) if @target.packet
        return if custom_method?(:write)

        line('Tick write(PacketPtr pkt) {')
        indent do
          line('Addr daddr = pkt->getAddr() - pioAddr;')
          line('uint8_t* data_ptr = pkt->getPtr<uint8_t>();')
          line('')
          if bank_backend?
            line('writeRegisters(pkt);')
          else
            dispatchable(:write).each { |r| emit_dispatch_case(r, :write) }
          end
          line('')
          line('pkt->makeResponse();')
          line('return pioDelay;')
        end
        line('}')
        line('')
      end

      def emit_dispatch_case(reg, access)
        return emit_policy_dispatch_case(reg, access) if @target.packet

        bytesize = reg.size
        seqsize = bytesize * (reg.seqn || 1)
        condition = "#{reg.offset} <= daddr && daddr < #{reg.offset} + #{seqsize}"
        condition += " && (#{expr(reg.enable_if)})" if reg.enable_if
        line("if (#{condition}) {")
        indent do
          if access == :read
            if reg.banked?
              line("uint64_t cid = (daddr - #{reg.offset}) / #{bytesize};")
              line("#{int_type(reg.size * 8)} read_data = #{reg.name}_read(cid);")
            else
              line("#{int_type(reg.size * 8)} read_data = #{reg.name}_read();")
            end
            line("std::memcpy(data_ptr, &read_data, #{bytesize});")
          else
            line("#{int_type(reg.size * 8)} write_data;")
            line("std::memcpy(&write_data, data_ptr, #{bytesize});")
            if reg.banked?
              line("uint64_t cid = (daddr - #{reg.offset}) / #{bytesize};")
              line("#{reg.name}_write(write_data, cid);")
            else
              line("#{reg.name}_write(write_data);")
            end
          end
        end
        line('}')
      end

      def emit_epilogue
        emit_addr_ranges unless custom_method?(:getAddrRanges)
        emit_framework_hooks
      end

      def emit_addr_ranges
        line('AddrRangeList getAddrRanges() const')
        line('{')
        indent do
          line('AddrRangeList ranges;')
          line('ranges.push_back(RangeSize(pioAddr, pioSize));')
          line('return ranges;')
        end
        line('}')
        line('')
      end

      def emit_framework_hooks
        emit_checkpoint if @device.checkpoint
        if @target.register_backend == 'legacy' && !@device.checkpoint && !custom_method?(:serialize)
          line('void serialize(CheckpointOut &cp) const override {}')
        end
        if @target.register_backend == 'legacy' && !@device.checkpoint && !custom_method?(:unserialize)
          line('void unserialize(CheckpointIn &cp) override {}')
        end
        line('')
        unless custom_method?(:getPort)
          default = @target.register_backend == 'legacy' ? '' : '=InvalidPortID'
          line("Port &getPort(const std::string &if_name, PortID idx#{default})")
          line('{')
          indent { @target.port_body.strip.lines.each { |l| line(l.strip) } }
          line('}')
          line('')
        end
        return if custom_method?(:init)

        line('void init()')
        line('{')
        indent do
          line('initRegisters();') if bank_backend?
          @target.init_body.strip.lines.each { |l| line(l.strip) }
        end
        line('}')
      end

      def stmt(node)
        case node.kind
        when :vardecl
          line("#{cpp_type(node.type)} #{node.name};")
        when :assign
          emit_assign(node)
        when :exprstmt
          line("#{expr(node.expr)};")
        when :if
          emit_if(node)
        when :for
          line("for (int #{node.iter} = #{expr(node.from)}; #{node.iter} < #{expr(node.to)}; ++#{node.iter}) {")
          indent { node.body.each { |s| stmt(s) } }
          line('}')
        when :return
          line(node.value ? "return #{expr(node.value)};" : 'return;')
        when :setelem
          line("#{indexed_expr(node.container, node.index)} = #{expr(node.value)};")
        when :initcall
          line("#{node.field}(#{node.args.map { |a| expr(a) }.join(', ')});")
        else
          raise Plod::Error, "cannot emit statement '#{node.kind}'"
        end
      end

      def emit_assign(node)
        target = node.target
        case target.kind
        when :regfield
          reg = register_operand(target.reg)
          field = find_field(reg, target.field)
          line("protea::_insert(#{reg_target_name(target.reg)}, #{field.lsb}, #{field.size}, #{expr(node.value)});")
        when :self
          line("#{reg_target_name(target)} = #{expr(node.value)};")
        else
          line("#{expr(target)} = #{expr(node.value)};")
        end
      end

      def emit_if(node)
        line("if (#{expr(node.cond)}) {")
        indent { node.then_body.each { |s| stmt(s) } }
        node.elsif_list.each do |cond, body|
          line("} else if (#{expr(cond)}) {")
          indent { body.each { |s| stmt(s) } }
        end
        if node.else_body
          line('} else {')
          indent { node.else_body.each { |s| stmt(s) } }
        end
        line('}')
      end

      def register_operand(node)
        case node.kind
        when :self then @register
        when :var then @device.registers.find { |r| r.name == node.name }
        else
          raise Plod::Error, "invalid register operand '#{node.kind}'"
        end
      end

      def reg_target_name(node)
        reg = register_operand(node)
        return register_value(reg, 'cid') if node.kind == :self && reg.banked?

        register_value(reg)
      end

      def find_field(reg, field_name)
        reg.fields.find { |f| f.name == field_name }
      end

      def expr(node)
        case node.kind
        when :var
          reg = @device.registers.find { |r| r.name == node.name }
          return register_value(reg) if reg && bank_backend? && !reg.banked?

          member = (@device.fields + @device.consts + @device.registers).any? { |f| f.name == node.name }
          prefix = (@checkpoint_emitting || @packet_emitting) && member ? 'this->' : ''
          "#{prefix}#{env_name(node.name)}"
        when :const
          if node.value.is_a?(String)
            "\"#{node.value}\""
          elsif node.value > 0x7fff_ffff_ffff_ffff
            "#{node.value}ULL"
          else
            node.value.to_s
          end
        when :self
          node.subject == :register ? register_value(@register) : 'this'
        when :selfindex
          'cid'
        when :binop
          "(#{expr(node.lhs)} #{BINOPS[node.op]} #{expr(node.rhs)})"
        when :unop
          "(~#{expr(node.operand)})"
        when :cast
          cast_expr(node)
        when :regfield
          reg = register_operand(node.reg)
          field = find_field(reg, node.field)
          "protea::_extract(#{reg_target_name(node.reg)}, #{field.lsb}, #{field.size})"
        when :getfield
          op = ptr_recv?(node.recv) ? '->' : '.'
          "#{expr(node.recv)}#{op}#{node.name}"
        when :getelem
          indexed_expr(node.container, node.index)
        when :enumval
          "#{node.enum}::#{node.key}"
        when :getptr
          "&#{expr(node.target)}"
        when :mcall
          method_call_expr(node)
        when :call
          member = @device.methods.any? { |m| m.name == node.name }
          prefix = (@checkpoint_emitting || @packet_emitting) && member ? 'this->' : ''
          "#{prefix}#{env_name(node.name)}(#{node.args.map { |a| expr(a) }.join(', ')})"
        else
          raise Plod::Error, "cannot emit expression '#{node.kind}'"
        end
      end

      def cast_expr(node)
        return "(#{expr(node.value)} != 0)" if node.type.is_a?(Types::Bool)

        return "(#{expr(node.value)})" if @target.register_backend == 'legacy'

        "static_cast<#{cpp_type(node.type)}>(#{expr(node.value)})"
      end

      def ptr_recv?(node)
        IR.node_type(node).is_a?(Types::Ptr)
      end

      def method_call_expr(node)
        recv = node.recv
        args = node.args.map { |a| expr(a) }
        if recv.kind == :self && recv.subject == :register && @register
          return "#{@register.name}_#{node.name}(#{args.join(', ')})"
        end

        if recv.kind == :var
          reg = @device.registers.find { |r| r.name == recv.name }
          return "#{reg.name}_#{node.name}(#{args.join(', ')})" if reg
        end
        recv_type = IR.node_type(recv)&.deref
        if node.name == :at && !recv_type.is_a?(Types::Map) && !recv_type.is_a?(Types::Str)
          return "#{expr(recv)}[#{args.join(', ')}]"
        end
        if %i[firstKey firstValue eraseFirst].include?(node.name) && recv_type.is_a?(Types::Map)
          return "protea::#{node.name}(#{expr(recv)})"
        end

        member = @target.env_rewrite("#{recv_type&.name}.#{node.name}") || node.name
        member = 'push_back' if node.name == :push && recv_type.is_a?(Types::Vector)
        member = 'insert_or_assign' if node.name == :put && recv_type.is_a?(Types::Map)

        op = ptr_recv?(recv) ? '->' : '.'
        "#{expr(recv)}#{op}#{member}(#{args.join(', ')})"
      end
    end
  end
end

require_relative 'cpp_registers'
require_relative 'cpp_packets'
require_relative 'cpp_checkpoint'
