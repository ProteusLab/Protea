require_relative "../../ADL/base"
require_relative "../../ADL/builder"

module SimInfra
    XReg = Operand(:XReg, :r32) do
        map { |name| let name, :XRegs, [:op], :r32, send("f_#{name}") }
    end

    IImm = Operand(:IImm, :s32) do
        map { |name| let name, [:op], :s32, send("f_#{name}").s32 }
    end

    UImm = Operand(:UImm, :s32) do
        map { |name| let name, [:op], :s32, (send("f_#{name}").s << 12) }
    end

    IsImm = Operand(:IsImm, :s32) do
        map { |name| let name, [:op], :s32, f_imm4_0 }
    end

    JImm = Operand(:JImm, :s32) do
        map { |name|
            let name, [:op], :s32,
                (f_imm20.b21 << 20 | f_imm19_12.b21 << 12 | f_imm11.b21 << 11 | f_imm10_1.b21 << 1).s32
        }
    end

    BImm = Operand(:BImm, :s32) do
        map { |name|
            let name, [:op], :s32,
                (f_imm12.b13 << 12 | f_imm11.b13 << 11 | f_imm10_5.b13 << 5 | f_imm4_1.b13 << 1).s32
        }
    end

    SImm = Operand(:SImm, :s32) do
        map { |name|
            let name, [:op], :s32, (f_imm11_5.b12 << 5 | f_imm4_0.b12).s32
        }
    end
end

module SimInfra
    def format_u(opcode)
        return :U, [
            field(:f_opcode, 6, 0, opcode),
            field(:f_rd, 11, 7),
            field(:f_imm, 31, 12),
        ], XReg[:rd], UImm[:imm]
    end

    def format_r(opcode, funct3, funct7)
        return :R, [
            field(:f_opcode, 6, 0, opcode),
            field(:f_rd, 11, 7),
            field(:f_funct3, 14, 12, funct3),
            field(:f_rs1, 19, 15),
            field(:f_rs2, 24, 20),
            field(:f_funct7, 31, 25, funct7),
        ], XReg[:rs2], XReg[:rs1], XReg[:rd]
    end

    def format_i(opcode, funct3)
        return :I, [
            field(:f_opcode, 6, 0, opcode),
            field(:f_rd, 11, 7),
            field(:f_funct3, 14, 12, funct3),
            field(:f_rs1, 19, 15),
            field(:f_imm, 31, 20),
        ], IImm[:imm], XReg[:rs1], XReg[:rd]
    end

    def format_i_shift(opcode, func3, funct7)
        return :I, [
            field(:f_opcode, 6, 0, opcode),
            field(:f_rd, 11, 7),
            field(:f_funct3, 14, 12, func3),
            field(:f_rs1, 19, 15),
            field(:f_imm11_5, 31, 25, funct7),
            field(:f_imm4_0, 24, 20),
        ], IsImm[:imm], XReg[:rs1], XReg[:rd]
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
        ], BImm[:imm], XReg[:rs1], XReg[:rs2]
    end

    def format_j(opcode)
        return :J, [
            field(:f_opcode, 6, 0, opcode),
            field(:f_rd, 11, 7),
            field(:f_imm20, 31, 31),
            field(:f_imm19_12, 19, 12),
            field(:f_imm11, 20, 20),
            field(:f_imm10_1, 30, 21),
        ], JImm[:imm], XReg[:rd]
    end

    def format_s(opcode, func3)
        return :S, [
            field(:f_opcode, 6, 0, opcode),
            field(:func3, 14, 12, func3),
            field(:f_imm4_0, 11, 7),
            field(:f_rs1, 19, 15),
            field(:f_rs2, 24, 20),
            field(:f_imm11_5, 31, 25),
        ], SImm[:imm], XReg[:rs1], XReg[:rs2]
    end
end
