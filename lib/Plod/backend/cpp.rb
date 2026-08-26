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

        preamble
        line('namespace gem5 {')
        line('')
        @device.fields.map(&:type).uniq.each { |t| emit_struct(t) if struct_type?(t) }
        device_class
        line('}')
        "#{@out.join("\n")}\n"
      end

      private

      def line(text = '')
        @out << (('    ' * @indent) + text)
      end

      def indent
        @indent += 1
        yield
        @indent -= 1
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
        when Types::Array then "std::array<#{cpp_type(type.elem)}, #{type.size}>"
        when Types::Ptr then "#{deref_cpp_name(type.stored)}*"
        when Types::Ref then "#{deref_cpp_name(type.stored)}&"
        when Types::Named then type.name
        else
          raise Plod::Error, "cannot map type '#{type.name}' to C++"
        end
      end

      def deref_cpp_name(stored)
        stored.is_a?(Types::Ptr) || stored.is_a?(Types::Ref) ? cpp_type(stored) : stored.name
      end

      def int_type(bits)
        return 'bool' if bits == 1

        return 'uint8_t' if bits <= 8
        return 'uint16_t' if bits <= 16
        return 'uint32_t' if bits <= 32

        'uint64_t'
      end

      def preamble
        line('#pragma once')
        line('')
        @target.includes.each do |inc|
          line(inc.start_with?('<') ? "#include #{inc}" : "#include \"#{inc}\"")
        end
        line('')
        line('namespace protea {')
        indent do
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
        line('}')
        line('')
      end

      def emit_struct(type)
        component = concrete_struct(type.id)
        return if @emitted_structs&.include?(component.name)

        @emitted_structs ||= []
        @emitted_structs << component.name

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
            line("#{ret} #{m.name}(#{args}) {")
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
          # rubocop:disable Lint/HashEachMethods -- EnumDecl#values is a DTO member (Array), not Hash#values
          indent { e.values.each { |k, v| line("#{k} = #{v},") } }
          # rubocop:enable Lint/HashEachMethods
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
          line(field_decl(f))
        end
        line('') unless @device.fields.empty?

        @device.registers.each do |r|
          line(register_storage(r))
        end
        line('') unless @device.registers.empty?

        @device.registers.each { |r| register_methods(r) }
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
        if reg.seqn
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
          if reg.seqn
            line("#{int_type(reg.size * 8)} #{reg.name}_read(uint64_t cid) { return #{reg.name}[cid]; }")
          else
            line("#{int_type(reg.size * 8)} #{reg.name}_read() { return #{reg.name}; }")
          end
        end

        return if reg.methods.any? { |m| m.name == :write }

        line('')
        if reg.seqn
          line("void #{reg.name}_write(#{int_type(reg.size * 8)} data, uint64_t cid) { #{reg.name}[cid] = data; }")
        else
          line("void #{reg.name}_write(#{int_type(reg.size * 8)} data) { #{reg.name} = data; }")
        end
      end

      def register_method(reg, m)
        ret = m.ret_type.nil? ? 'void' : cpp_type(m.ret_type)
        args = m.args.map { |n, t| "#{cpp_type(t)} #{n}" }.join(', ')
        line("#{ret} #{reg.name}_#{m.name}(#{args}) {")
        indent { m.body.each { |s| stmt(s) } }
        line('}')
      end

      def device_public
        @device.methods.reject(&:abstract).each do |m|
          ret = m.ret_type.nil? ? 'void' : cpp_type(m.ret_type)
          args = m.args.map { |n, t| "#{cpp_type(t)} #{n}" }.join(', ')
          line("#{ret} #{m.name}(#{args}) {")
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
        full_init = ([base_init] + init_list).join(', ')
        line("#{@device.name}(const #{@device.name}Params &params)")
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
        line('Tick read(PacketPtr pkt) override {')
        indent do
          line('uint64_t daddr = pkt->getAddr() - pioAddr;')
          line('uint8_t* data_ptr = pkt->getPtr<uint8_t>();')
          line('')
          dispatchable(:read).each do |r|
            emit_dispatch_case(r, :read)
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
        line('Tick write(PacketPtr pkt) {')
        indent do
          line('Addr daddr = pkt->getAddr() - pioAddr;')
          line('uint8_t* data_ptr = pkt->getPtr<uint8_t>();')
          line('')
          dispatchable(:write).each do |r|
            emit_dispatch_case(r, :write)
          end
          line('')
          line('pkt->makeResponse();')
          line('return pioDelay;')
        end
        line('}')
        line('')
      end

      def emit_dispatch_case(reg, access)
        bytesize = reg.size
        seqsize = bytesize * (reg.seqn || 1)
        condition = "#{reg.offset} <= daddr && daddr < #{reg.offset} + #{seqsize}"
        condition += " && (#{expr(reg.enable_if)})" if reg.enable_if
        line("if (#{condition}) {")
        indent do
          if access == :read
            if reg.seqn
              line("uint64_t cid = (daddr - #{reg.offset}) / #{bytesize};")
              line("#{int_type(reg.size * 8)} read_data = #{reg.name}_read(cid);")
            else
              line("#{int_type(reg.size * 8)} read_data = #{reg.name}_read();")
            end
            line("std::memcpy(data_ptr, &read_data, #{bytesize});")
          else
            line("#{int_type(reg.size * 8)} write_data;")
            line("std::memcpy(&write_data, data_ptr, #{bytesize});")
            if reg.seqn
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
        line('AddrRangeList getAddrRanges() const')
        line('{')
        indent do
          line('AddrRangeList ranges;')
          line('ranges.push_back(RangeSize(pioAddr, pioSize));')
          line('return ranges;')
        end
        line('}')
        line('')
        line('void serialize(CheckpointOut &cp) const override {}')
        line('void unserialize(CheckpointIn &cp) override {}')
        line('')
        line('Port &getPort(const std::string &if_name, PortID idx)')
        line('{')
        indent { @target.port_body.strip.lines.each { |l| line(l.strip) } }
        line('}')
        line('')
        line('void init()')
        line('{')
        indent { @target.init_body.strip.lines.each { |l| line(l.strip) } }
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
          line("#{expr(node.container)}[#{expr(node.index)}] = #{expr(node.value)};")
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
          line("protea::_insert(#{reg.name}, #{field.lsb}, #{field.size}, #{expr(node.value)});")
        when :self
          line("#{register_operand(target).name} = #{expr(node.value)};")
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

      def find_field(reg, field_name)
        reg.fields.find { |f| f.name == field_name }
      end

      def expr(node)
        case node.kind
        when :var
          env_name(node.name)
        when :const
          node.value.is_a?(String) ? "\"#{node.value}\"" : node.value.to_s
        when :self
          node.subject == :register ? @register.name : 'this'
        when :binop
          "(#{expr(node.lhs)} #{BINOPS[node.op]} #{expr(node.rhs)})"
        when :unop
          "(~#{expr(node.operand)})"
        when :cast
          cast_expr(node)
        when :regfield
          reg = register_operand(node.reg)
          field = find_field(reg, node.field)
          "protea::_extract(#{reg.name}, #{field.lsb}, #{field.size})"
        when :getfield
          op = ptr_recv?(node.recv) ? '->' : '.'
          "#{expr(node.recv)}#{op}#{node.name}"
        when :getelem
          "#{expr(node.container)}[#{expr(node.index)}]"
        when :enumval
          "#{node.enum}::#{node.key}"
        when :getptr
          "&#{expr(node.target)}"
        when :mcall
          method_call_expr(node)
        when :call
          "#{node.name}(#{node.args.map { |a| expr(a) }.join(', ')})"
        else
          raise Plod::Error, "cannot emit expression '#{node.kind}'"
        end
      end

      def cast_expr(node)
        return "(#{expr(node.value)} != 0)" if node.type.is_a?(Types::Bool)

        "(#{expr(node.value)})"
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
        return "#{expr(recv)}[#{args.join(', ')}]" if node.name == :at

        op = ptr_recv?(recv) ? '->' : '.'
        "#{expr(recv)}#{op}#{node.name}(#{args.join(', ')})"
      end
    end
  end
end
