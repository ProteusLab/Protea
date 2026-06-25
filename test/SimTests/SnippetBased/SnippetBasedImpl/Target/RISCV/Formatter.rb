# frozen_string_literal: true

module SimTest
  class RiscVFormatter
    def prologue(emitter)
      emitter.emit_line '.global _start'
      emitter.emit_line '.section .text'
      emitter.emit_line '_start:'
      emitter.increase_indent
    end

    def init_register(emitter, ir, values)
      ir[:regfiles].each do |regfile|
        regfile[:regs].each do |reg|
          attrs = reg[:attrs] || []
          next if attrs.include?(:zero) || attrs.include?(:pc) || reg[:name] == :x2

          emitter.emit_line "li #{reg[:name]}, 0x#{values[reg[:name]].to_s(16)}"
        end
      end
    end

    def insert_snippet(emitter, snippet_content)
      snippet_content.each_line do |line|
        emitter.emit_line line.chomp
      end
    end

    def insert_check(emitter, ir, ref_values)
      emitter.emit_line 'addi sp, sp, -4'
      emitter.emit_line 'sw x1, 4(sp)'
      ir[:regfiles].each do |regfile|
        regfile[:regs].each do |reg|
          attrs = reg[:attrs] || []
          next if attrs.include?(:zero) || attrs.include?(:pc) || reg[:name] == :x1 || reg[:name] == :x2

          emitter.emit_line "li x1, 0x#{ref_values[reg[:name]].to_s(16)}"
          emitter.emit_line "bne x1, #{reg[:name]}, _fail"
        end
      end
      emitter.emit_line 'lw x3, 4(sp)'
      emitter.emit_line "li x1, 0x#{ref_values[:x1].to_s(16)}"
      emitter.emit_line 'addi sp, sp, 4'
      emitter.emit_line 'bne x1, x3, _fail'
    end

    def epilogue(emitter)
      emitter.emit_line 'li a0, 0'
      emitter.emit_line 'li a7, 93'
      emitter.emit_line 'ecall'
      emitter.emit_blank_line
      emitter.decrease_indent
      emitter.emit_line '_fail:'
      emitter.increase_indent
      emitter.emit_line 'li a0, 1'
      emitter.emit_line 'li a7, 93'
      emitter.emit_line 'ecall'
      emitter.decrease_indent
      emitter.emit_blank_line
    end
  end
end
