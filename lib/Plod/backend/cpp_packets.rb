# frozen_string_literal: true

module Plod
  module Backend
    class Cpp
      private

      def validate_packet_policy
        policy = @target.packet
        if custom_method?(:read) || custom_method?(:write)
          raise Plod::Error, 'packet policy conflicts with handwritten read/write methods'
        end

        validate_packet_latency(policy[:latency])
        policy[:after_write].each do |name|
          method = @device.methods.find { |m| m.name == name.to_sym }
          unless method && !method.abstract && method.args.empty? && method.ret_type.nil?
            raise Plod::Error, "packet hook #{name} must be a concrete zero-argument void device method"
          end
        end
        if bank_backend?
          if @device.registers.any?(&:address) || policy[:read_response] != 'after_payload'
            raise Plod::Error, 'native bank packet access requires relative registers and after_payload reads'
          end
        elsif !policy[:width] || @device.registers.any? { |r| r.layout || r.size != policy[:width] }
          raise Plod::Error, 'direct packet access requires a width matching each scalar/Seqn register'
        end
        if policy[:atomic_swap] && policy[:read_response] != 'after_payload'
          raise Plod::Error, 'atomic swaps require after_payload reads'
        end

        validate_packet_forward(policy[:forward]) if policy[:forward]
      end

      def validate_packet_latency(value)
        return if value.is_a?(Integer)

        field = (@device.fields + @device.consts).find { |f| f.name == value.to_sym }
        raise Plod::Error, "packet latency #{value} must reference numeric device state" unless field&.type&.numeric?
      end

      def validate_packet_forward(forward)
        validate_packet_latency(forward[:latency])
        field = @device.fields.find { |f| f.name == forward[:receiver].to_sym }
        type = field&.type&.deref
        component = type.is_a?(Types::Named) && @program.components.find { |c| c.name == type.id }
        valid = component && %i[read write].all? do |access|
          method = component.methods.find { |m| m.name == forward[access].to_sym }
          method && method.ret_type.nil? && method.args.map(&:last) ==
            [Types::Ptr.new(Types::Named.new(:Packet)), Types::Bits.new(64)]
        end
        raise Plod::Error, 'packet forwarding requires declared void methods taking (Packet*, b64)' unless valid
      end

      def emit_policy_packet(access)
        @packet_emitting = true
        policy = @target.packet
        line("Tick #{access}(PacketPtr pkt) override {")
        indent do
          if policy[:forward] || (!bank_backend? && @device.registers.any? { |reg| !reg.address })
            line('Addr daddr = pkt->getAddr() - pioAddr;')
          end
          emit_packet_forward(access) if policy[:forward]
          if policy[:width]
            condition = "pkt->getSize() == #{policy[:width]}"
            check = if policy[:check] == 'assert'
                      "assert(#{condition});"
                    else
                      "panic_if(!(#{condition}), \"Unexpected access size\");"
                    end
            line(check)
          end
          line('const bool is_atomic = protea::isAtomicSwap(pkt);') if access == :read && policy[:atomic_swap]
          emit_packet_response if access == :write && policy[:write_response] == 'before_dispatch'
          if bank_backend?
            line("#{access}Registers(pkt);")
          else
            emit_packet_dispatch(access)
          end
          if access == :read && policy[:atomic_swap]
            line('if (is_atomic) {')
            indent do
              line('protea::applyAtomic(pkt);')
              line('return write(pkt);')
            end
            line('}')
          end
          policy[:after_write].each { |name| line("this->#{name}();") } if access == :write
          if access == :read && policy[:read_response] == 'before_payload'
            emit_packet_response
            line("if (has_data) pkt->setLE<#{int_type(policy[:width] * 8)}>(read_data);")
          elsif access == :read || policy[:write_response] == 'after_dispatch'
            emit_packet_response
          end
          line("return #{packet_latency(policy[:latency])};")
        end
        line('}')
        line('')
      ensure
        @packet_emitting = false
      end

      def packet_latency(value)
        value.is_a?(Integer) ? value.to_s : "this->#{env_name(value)}"
      end

      def emit_packet_forward(access)
        forward = @target.packet[:forward]
        field = @device.fields.find { |f| f.name == forward[:receiver].to_sym }
        type = field.type.deref
        method = @target.env_rewrite("#{type.name}.#{forward[access]}") || forward[access]
        op = field.type.is_a?(Types::Ptr) ? '->' : '.'
        line("if (daddr >= #{forward[:start]}) {")
        indent do
          line("this->#{forward[:receiver]}#{op}#{method}(pkt, daddr - #{forward[:start]});")
          line("return #{packet_latency(forward[:latency])};")
        end
        line('}')
      end

      def emit_packet_response
        method = @target.packet[:response] == 'atomic' ? 'makeAtomicResponse' : 'makeResponse'
        line("pkt->#{method}();")
      end

      def emit_packet_dispatch(access)
        policy = @target.packet
        line('bool matched = false;')
        if access == :read && policy[:read_response] == 'before_payload'
          line("#{int_type(policy[:width] * 8)} read_data = 0;")
          line('bool has_data = false;')
        end
        dispatchable(access).each { |reg| emit_dispatch_case(reg, access) }
        (@device.registers - dispatchable(access)).each do |reg|
          line("if (!matched && (#{packet_register_condition(reg)})) {")
          indent do
            line('matched = true;')
            if policy[:denied] == 'warn'
              line("warn(\"Guest is trying to #{access} a #{access == :read ? 'write' : 'read'}-only register\");")
              emit_packet_read_value('0', reg) if access == :read
            elsif policy[:denied] == 'panic'
              line("panic(\"Forbidden #{access} access\");")
            end
          end
          line('}')
        end
        line("panic_if(!matched, \"Unhandled #{access} address\");") if policy[:unmapped] == 'panic'
      end

      def packet_register_condition(reg)
        address = reg.address ? expr(reg.address) : reg.offset.to_s
        offset = reg.address ? "(pkt->getAddr() - (#{address}))" : "(daddr - #{address})"
        condition = if reg.banked?
                      "#{offset} < #{reg.size * reg.seqn} && #{offset} % #{reg.size} == 0"
                    else
                      "#{reg.address ? 'pkt->getAddr()' : 'daddr'} == #{address}"
                    end
        condition += " && (#{expr(reg.enable_if)})" if reg.enable_if
        condition
      end

      def emit_policy_dispatch_case(reg, access)
        guard = @target.packet[:match] == 'first' ? '!matched && ' : ''
        line("if (#{guard}(#{packet_register_condition(reg)})) {")
        indent do
          line('matched = true;')
          if reg.banked?
            base = reg.address ? "pkt->getAddr() - (#{expr(reg.address)})" : "daddr - #{reg.offset}"
            line("uint64_t cid = (#{base}) / #{reg.size};")
          end
          if access == :read
            emit_packet_read_value("#{reg.name}_read(#{'cid' if reg.banked?})", reg)
          else
            data = "pkt->getLE<#{int_type(reg.size * 8)}>()"
            line("#{reg.name}_write(#{data}#{', cid' if reg.banked?});")
          end
        end
        line('}')
      end

      def emit_packet_read_value(value, reg)
        if @target.packet[:read_response] == 'before_payload'
          line("read_data = #{value};")
          line('has_data = true;')
        else
          line("pkt->setLE<#{int_type(reg.size * 8)}>(#{value});")
        end
      end
    end
  end
end
