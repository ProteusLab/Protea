require_relative "encoding"
require "Generic/base"
require "Generic/builder"

module Ops
    
    class Add; def self.op(a, b); a.u + b.u; end; end
    class Sub; def self.op(a, b); a.u - b.u; end; end
    class Sll; def self.op(a, b); a.u << b.u; end; end
    class Slt; def self.op(a, b); (a.s < b.s).b; end; end
    class Sltu; def self.op(a, b); (a.u < b.u).b; end; end
    class Xor; def self.op(a, b); a ^ b; end; end
    class Srl; def self.op(a, b); a.u >> b.u; end; end
    class Sra; def self.op(a, b); a.s >> b.u; end; end
    class Or;  def self.op(a, b); a | b; end; end
    class And; def self.op(a, b); a & b; end; end
    class Load8; def self.op(rs1, imm); mem[rs1 + imm, :b8].s32; end; end
    class Load16; def self.op(rs1, imm); mem[rs1 + imm, :b16].s32; end; end
    class Load32; def self.op(rs1, imm); mem[rs1 + imm, :b32]; end; end
    class Load8U; def self.op(rs1, imm); mem[rs1 + imm, :b8].u32; end; end
    class Load16U; def self.op(rs1, imm); mem[rs1 + imm, :b16].u32; end; end

end

module RV32I
    include SimInfra
    extend SimInfra

    RegisterFile(:XRegs) {
        r32 :x0, zero
        for x in (1..31); r32 "x" + x.to_s; end 
        r32 :pc
    }

    Instruction(:lui) {
        encoding *format_u(0b0110111)
        asm { "lui {rd}, {imm}" }
        code { rd[]= imm }
    }

    Instruction(:auipc) {
        encoding *format_u(0b0010111)
        asm { "auipc {rd}, {imm}" }
        code { rd[]= imm + pc }
    }

    TABLE_R_FORMAT_INSTRUCTIONS = [
        [:add, format_r(0b0110011, 0b000, 0b0000000), Ops::Add],
        [:sub, format_r(0b0110011, 0b000, 0b0100000), Ops::Sub],
        [:sll, format_r(0b0110011, 0b001, 0b0000000), Ops::Sll],
        [:slt, format_r(0b0110011, 0b010, 0b0000000), Ops::Slt],
        [:sltu, format_r(0b0110011, 0b011, 0b0000000), Ops::Sltu],
        [:xor, format_r(0b0110011, 0b100, 0b0000000), Ops::Xor],
        [:srl, format_r(0b0110011, 0b101, 0b0000000), Ops::Srl],
        [:sra, format_r(0b0110011, 0b101, 0b0100000), Ops::Sra],
        [:or,  format_r(0b0110011, 0b110, 0b0000000), Ops::Or],
        [:and, format_r(0b0110011, 0b111, 0b0000000), Ops::And],
    ]

    for insn in TABLE_R_FORMAT_INSTRUCTIONS
        Instruction(insn[0]) {
            encoding *insn[1]
            asm { insn[0].to_s + "{rd}, {rs1}, {rs2}" }
            code { rd[]= insn[2].op(rs1, rs2) }
        }
    end

    TABLE_I_FORMAT_INSTRUCTIONS = [
        [:addi, format_i(0b0010011, 0b000), Ops::Add],
        [:xori, format_i(0b0010011, 0b100), Ops::Xor],
        [:ori,  format_i(0b0010011, 0b110), Ops::Or],
        [:andi, format_i(0b0010011, 0b111), Ops::And],
    ]

    for insn in TABLE_I_FORMAT_INSTRUCTIONS
        Instruction(insn[0]) {
            encoding *insn[1]
            asm { insn[0].to_s + "{rd}, {rs1}, {imm}" }
            code { rd[]= insn[2].op(rs1, imm) }
        }
    end

    Instruction(:beq) {
        encoding *format_b(0b1100011, 0b000)
        asm { "beq {rs1}, {rs2}, {imm}" }
        code { branch(select(rs1 == rs2, pc + imm, pc + xlen)) }
    }

    Instruction(:bne) {
        encoding *format_b(0b1100011, 0b001)
        asm { "bne {rs1}, {rs2}, {imm}" }
        code { branch(select(rs1 != rs2, pc + imm, pc + xlen)) }
    }

    Instruction(:blt) {
        encoding *format_b(0b1100011, 0b100)
        asm { "blt {rs1}, {rs2}, {imm}" }
        code { branch(select(rs1 < rs2, pc + imm, pc + xlen)) }
    }

    Instruction(:bge) {
        encoding *format_b(0b1100011, 0b101)
        asm { "bge {rs1}, {rs2}, {imm}" }
        code { branch(select(rs1 > rs2, pc + imm, pc + xlen)) }
    }

    Instruction(:bltu) {
        encoding *format_b(0b1100011, 0b110)
        asm { "bltu {rs1}, {rs2}, {imm}" }
        code { branch(select(rs1.u < rs2.u, pc + imm, pc + xlen)) }
    }

    Instruction(:bgeu) {
        encoding *format_b(0b1100011, 0b111)
        asm { "bgeu {rs1}, {rs2}, {imm}" }
        code { branch(select(rs1.u > rs2.u, pc + imm, pc + xlen)) }
    }

    Instruction(:jal) {
        encoding *format_j(0b1101111)
        asm { "jal {rd}, {imm}" }
        code { rd[]= pc + xlen; branch(pc + imm) }
    }

    Instruction(:jalr) {
        encoding *format_i(0b1101111, 0b000)
        asm { "jalr {rd}, {rs1}, {imm}" }
        code { 
          let :t, :b32, pc + xlen
          branch((rs1 + imm) & (~1))
          rd[]= t
        }
    }

    Instruction(:sb) {
        encoding *format_s(0b0100011, 0b000)
        asm { "sb {rs2}, {imm}({rs1})" }
        code { mem[rs1 + imm]= rs2[7, 0] }
    }

    Instruction(:sh) {
        encoding *format_s(0b0100011, 0b001)
        asm { "sh {rs2}, {imm}({rs1})" }
        code { mem[rs1 + imm]= rs2[15, 0] }
    }

    Instruction(:sw) {
        encoding *format_s(0b0100011, 0b010)
        asm { "sw {rs2}, {imm}({rs1})" }
        code { mem[rs1 + imm]= rs2 }
    }

    Instruction(:lb) {
        encoding *format_i(0b0100011, 0b000)
        asm { "lb {rd}, {imm}({rs1})" }
        code { rd[]= mem[rs1 + imm, :b8].s32 }
    }

    Instruction(:lh) {
        encoding *format_i(0b0100011, 0b001)
        asm { "lh {rd}, {imm}({rs1})" }
        code { rd[]= mem[rs1 + imm, :b16].s32 }
    }

    Instruction(:lw) {
        encoding *format_i(0b0100011, 0b010)
        asm { "lw {rd}, {imm}({rs1})" }
        code { rd[]= mem[rs1 + imm, :b32] }
    }
    
    Instruction(:lbu) {
        encoding *format_i(0b0100011, 0b100)
        asm { "lbu {rd}, {imm}({rs1})" }
        code { rd[]= mem[rs1 + imm, :b8].u32 }
    }

    Instruction(:lhu) {
        encoding *format_i(0b0100011, 0b101)
        asm { "lhu {rd}, {imm}({rs1})" }
        code { rd[]= mem[rs1 + imm, :b16].u32 }
    }

    Instruction(:ecall) {
        encoding :E, [field(:c, 31, 0, 0b1110011)]
        asm { "ecall" }
        code { }
    }

    Instruction(:ebreak) {
        encoding :E, [field(:c, 31, 0, 0b100000000000001110011)]
        asm { "ebreak" }
        code { }
    }
end
