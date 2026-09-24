require "Common/base"

module Protea
    def u_imm(imm)
        return imm, :s32, "let :#{imm}, [:op], :s32, f_#{imm}.s << 12"
    end

    def i_imm(imm)
        return imm, :s32, "let :#{imm}, [:op], :s32, f_#{imm}.s32"
    end

    def is_imm(imm)
        return imm, :s32, "let :#{imm}, [:op], :s32, f_imm4_0"
    end

    def j_imm(imm)
        return imm, :s32, "let :#{imm}, [:op], :s32, (f_imm20.b21 << 20 | f_imm19_12.b21 << 12 | f_imm11.b21 << 11 | f_imm10_1.b21 << 1).s32"
    end

    def b_imm(imm)
        return imm, :s32, "let :#{imm}, [:op], :s32, (f_imm12.b13 << 12 | f_imm11.b13 << 11 | f_imm10_5.b13 << 5 | f_imm4_1.b13 << 1).s32"
    end

    def s_imm(imm)
        return imm, :s32, "let :#{imm}, [:op], :s32, (f_imm11_5.b12 << 5 | f_imm4_0.b12).s32"
    end

    def xreg(name)
        return name, :r32, "let :#{name}, :XRegs, [:op], :r32, f_#{name}"
    end
end

module Protea
    def format_u(opcode)
        return :U, [
            field(:f_opcode, 6, 0, opcode),
            field(:f_rd, 11, 7),
            field(:f_imm, 31, 12),
        ], xreg(:rd), u_imm(:imm)
    end

    def format_r(opcode, funct3, funct7)
        return :R, [
            field(:f_opcode, 6, 0, opcode),
            field(:f_rd, 11, 7),
            field(:f_funct3, 14, 12, funct3),
            field(:f_rs1, 19, 15),
            field(:f_rs2, 24, 20),
            field(:f_funct7, 31, 25, funct7),
        ], xreg(:rs2), xreg(:rs1), xreg(:rd)
    end

    def format_i(opcode, funct3)
        return :I, [
            field(:f_opcode, 6, 0, opcode),
            field(:f_rd, 11, 7),
            field(:f_funct3, 14, 12, funct3),
            field(:f_rs1, 19, 15),
            field(:f_imm, 31, 20),
        ], i_imm(:imm), xreg(:rs1), xreg(:rd)
    end

    def format_i_shift(opcode, func3, sopcode)
        return :srai, [
            field(:f_opcode, 6, 0, opcode),
            field(:func3, 14, 12, func3),
            field(:f_imm4_0, 24, 20),
            field(:f_rd, 11, 7),
            field(:f_rs1, 19, 15),
            field(:f_temp, 26, 25, 0b01),
            field(:f_sopcode, 31, 27, sopcode),
        ], is_imm(:imm), xreg(:rs1), xreg(:rd)
    end

    def format_b(opcode, funct3)
        return :B, [
            field(:f_opcode, 6, 0, opcode),
            field(:f_funct3, 14, 12, funct3),
            field(:f_rs1, 19, 15),
            field(:f_rs2, 24, 20),
            field(:f_imm4_1, 11, 8),
            field(:f_imm10_5, 30, 25),
            field(:f_imm11, 7, 7),
            field(:f_imm12, 31, 31),
        ], b_imm(:imm), xreg(:rs1), xreg(:rs2)
    end

    def format_j(opcode)
        return :J, [
            field(:f_opcode, 6, 0, opcode),
            field(:f_rd, 11, 7),
            field(:f_imm20, 31, 31),
            field(:f_imm19_12, 19, 12),
            field(:f_imm11, 20, 20),
            field(:f_imm10_1, 30, 21),
        ], j_imm(:imm), xreg(:rd)
    end

    def format_s(opcode, func3)
        return :S, [
            field(:f_opcode, 6, 0, opcode),
            field(:func3, 14, 12, func3),
            field(:f_imm4_0, 11, 7),
            field(:f_rs1, 19, 15),
            field(:f_rs2, 24, 20),
            field(:f_imm11_5, 31, 25),
        ], s_imm(:imm), xreg(:rs1), xreg(:rs2)
    end
end
