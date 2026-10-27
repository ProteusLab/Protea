require_relative "../../ADL/base"
require_relative "../../ADL/builder"

module SimInfra
    XReg = Operand(:XReg, :r32, :XRegs)

    IImm = Operand(:IImm, :s32) { f_imm.s32 }

    UImm = Operand(:UImm, :s32) { f_imm.s32 << 12 }

    IsImm = Operand(:IsImm, :s32) { f_imm4_0 }

    JImm = Operand(:JImm, :s32) {
        # imm[20] ← word[31], imm[19:12] ← word[19:12], imm[11] ← word[20], imm[10:1] ← word[30:21]
        f_imm20.s32 << 20 | f_imm19_12.u32 << 12 | f_imm11.u32 << 11 | f_imm10_1.u32 << 1
    }

    BImm = Operand(:BImm, :s32) {
        # imm[12] ← word[31], imm[11] ← word[7], imm[10:5] ← word[30:25], imm[4:1] ← word[11:8]
        f_imm12.s32 << 12 | f_imm11.u32 << 11 | f_imm10_5.u32 << 5 | f_imm4_1.u32 << 1
    }

    SImm = Operand(:SImm, :s32) {
        # imm[11:5] ← word[31:25], imm[4:0] ← word[11:7]
        f_imm11_5.s32 << 5 | f_imm4_0.u32
    }
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
            field(:f_imm4_1, 11, 8),     # → imm[4:1]
            field(:f_imm10_5, 30, 25),   # → imm[10:5]
            field(:f_imm11, 7, 7),       # → imm[11]
            field(:f_imm12, 31, 31),     # → imm[12]
        ], BImm[:imm], XReg[:rs1], XReg[:rs2]
    end

    def format_j(opcode)
        return :J, [
            field(:f_opcode, 6, 0, opcode),
            field(:f_rd, 11, 7),
            field(:f_imm20, 31, 31),     # → imm[20]
            field(:f_imm19_12, 19, 12),  # → imm[19:12]
            field(:f_imm11, 20, 20),     # → imm[11]
            field(:f_imm10_1, 30, 21),   # → imm[10:1]
        ], JImm[:imm], XReg[:rd]
    end

    def format_s(opcode, func3)
        return :S, [
            field(:f_opcode, 6, 0, opcode),
            field(:f_func3, 14, 12, func3),
            field(:f_imm4_0, 11, 7),     # → imm[4:0]
            field(:f_rs1, 19, 15),
            field(:f_rs2, 24, 20),
            field(:f_imm11_5, 31, 25),   # → imm[11:5]
        ], SImm[:imm], XReg[:rs1], XReg[:rs2]
    end
end
