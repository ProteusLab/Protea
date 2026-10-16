# frozen_string_literal: true

module Plod
  module Backend
    class Cpp
      private

      def emit_checkpoint
        if custom_method?(:serialize) || custom_method?(:unserialize)
          raise Plod::Error, 'Checkpoint conflicts with handwritten serialize/unserialize methods'
        end

        @checkpoint_emitting = true
        [true, false].each do |save|
          method = save ? 'serialize(CheckpointOut& cp) const' : 'unserialize(CheckpointIn& cp)'
          line("void #{method} override {")
          indent { emit_checkpoint_entries(@device.checkpoint.entries, save) }
          line('}')
          line('')
        end
      ensure
        @checkpoint_emitting = false
      end

      def emit_checkpoint_entries(entries, save)
        entries.each do |entry|
          case entry.kind
          when :checkpointvalue
            function = entry.encoding == :array ? 'arrayParam' : 'param'
            if bank_backend? && entry.encoding == :array && entry.destination.kind == :var &&
               @device.registers.any? { |reg| reg.name == entry.destination.name && reg.banked? }
              raise Plod::Error, 'checkpoint native bank arrays require Repeat with scalar entries'
            end

            line("#{function}#{save ? 'Out' : 'In'}(cp, #{expr(entry.key)}, #{expr(entry.destination)});")
          when :checkpointrepeat
            line("for (int #{entry.iter} = 0; #{entry.iter} < #{expr(entry.count)}; ++#{entry.iter}) {")
            indent { emit_checkpoint_entries(entry.entries, save) }
            line('}')
          when :checkpointmap
            emit_checkpoint_map(entry, save)
          when :checkpointdelegate
            method = save ? 'serialize' : 'unserialize'
            line("#{expr(entry.destination)}.#{method}(#{expr(entry.prefix)}, cp);")
          when :checkpointinherit
            line("#{@target.base}::#{save ? 'serialize' : 'unserialize'}(cp);")
          when :checkpointhook
            line("this->#{entry.name}();") unless save
          else
            raise Plod::Error, "unsupported checkpoint entry #{entry.kind}"
          end
        end
      end

      def emit_checkpoint_map(entry, save)
        type = IR.node_type(entry.destination)
        destination = expr(entry.destination)
        line('{')
        indent do
          if save
            line("int #{entry.iter} = 0;")
            line("for (const auto& _plod_entry : #{destination}) {")
            indent do
              line("const auto& #{entry.key_name} = _plod_entry.first;")
              line("const auto& #{entry.value_name} = _plod_entry.second;")
              emit_checkpoint_entries(entry.entries, true)
              line("++#{entry.iter};")
            end
            line('}')
            line("paramOut(cp, #{expr(entry.key)}, static_cast<#{cpp_type(entry.count_type)}>(#{destination}.size()));")
          else
            line("#{cpp_type(entry.count_type)} _plod_count;")
            line("paramIn(cp, #{expr(entry.key)}, _plod_count);")
            line("for (int #{entry.iter} = 0; #{entry.iter} < _plod_count; ++#{entry.iter}) {")
            indent do
              line("#{cpp_type(type.key)} #{entry.key_name}{};")
              line("#{cpp_type(type.elem)} #{entry.value_name}{};")
              emit_checkpoint_entries(entry.entries, false)
              line("#{destination}.insert_or_assign(#{entry.key_name}, #{entry.value_name});")
            end
            line('}')
          end
        end
        line('}')
      end
    end
  end
end
