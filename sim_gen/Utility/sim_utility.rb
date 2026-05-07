module SimGen
  module Helper
    module_function

      def find_max_regsize(regfiles)
        max_xlen = 0
        regfiles.each do |regfile|
          regfile[:regs].each do |reg|
            max_xlen = [max_xlen, reg[:size]].max
          end
        end
        max_xlen
      end

      def find_max_insn_len(instructions)
        max_len = 0
        instructions.each do |insn|
          insn[:code][:tree].each do |node|
            len_insn = node[:fields].map { |f| f[:from] - f[:to] }.sum / 8
            max_len = [max_len, len_insn].max
          end
        end
        max_len
  end
end
