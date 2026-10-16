require_relative "encoding"
require "Common/base"
require "ADL/builder"

module RV32I
    include Protea
    extend Protea

    Interface {
        function :sysCall
    }

    RegisterFile(:XRegs) {
        r32  :x0, zero
        r32  :x1
        r32  :x2
        r32  :x3
        r32  :x4
        r32  :x5
        r32  :x6
        r32  :x7
        r32  :x8
        r32  :x9
        r32 :x10
        r32 :x11
        r32 :x12
        r32 :x13
        r32 :x14
        r32 :x15
        r32 :x16
        r32 :x17
        r32 :x18
        r32 :x19
        r32 :x20
        r32 :x21
        r32 :x22
        r32 :x23
        r32 :x24
        r32 :x25
        r32 :x26
        r32 :x27
        r32 :x28
        r32 :x29
        r32 :x30
        r32 :x31
        r32  :pc, pc
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

    Instruction(:add) {
        encoding *format_r(0b0110011, 0b000, 0b0000000)
        asm { "add {rd}, {rs1}, {rs2}" }
        code { rd[]= rs1.u + rs2.u }
    }

    Instruction(:sub) {
        encoding *format_r(0b0110011, 0b000, 0b0100000)
        asm { "sub {rd}, {rs1}, {rs2}" }
        code { rd[]= rs1.u - rs2.u }
    }

    Instruction(:sll) {
        encoding *format_r(0b0110011, 0b001, 0b0000000)
        asm { "sll {rd}, {rs1}, {rs2}" }
        code { rd[]= rs1.u << rs2.u }
    }

    Instruction(:slt) {
        encoding *format_r(0b0110011, 0b010, 0b0000000)
        asm { "slt {rd}, {rs1}, {rs2}" }
        code { rd[]= (rs1.s < rs2.s).b32 }
    }

    Instruction(:sltu) {
        encoding *format_r(0b0110011, 0b011, 0b0000000)
        asm { "sltu {rd}, {rs1}, {rs2}" }
        code { rd[]= (rs1.u < rs2.u).b32 }
    }

    Instruction(:xor) {
        encoding *format_r(0b0110011, 0b100, 0b0000000)
        asm { "xor {rd}, {rs1}, {rs2}" }
        code { rd[]= rs1 ^ rs2 }
    }

    Instruction(:srl) {
        encoding *format_r(0b0110011, 0b101, 0b0000000)
        asm { "srl {rd}, {rs1}, {rs2}" }
        code { rd[]= rs1.u >> rs2.u }
    }

    Instruction(:sra) {
        encoding *format_r(0b0110011, 0b101, 0b0100000)
        asm { "sra {rd}, {rs1}, {rs2}" }
        code { rd[]= rs1.s >> rs2.s }
    }

    Instruction(:or) {
        encoding *format_r(0b0110011, 0b110, 0b0000000)
        asm { "or {rd}, {rs1}, {rs2}" }
        code { rd[]= rs1 | rs2 }
    }

    Instruction(:and) {
        encoding *format_r(0b0110011, 0b111, 0b0000000)
        asm { "and {rd}, {rs1}, {rs2}" }
        code { rd[]= rs1 & rs2 }
    }

    Instruction(:addi) {
        encoding *format_i(0b0010011, 0b000)
        asm { "addi {rd}, {rs1}, {imm}" }
        code { rd[]= rs1 + imm }
    }

    Instruction(:slti) {
        encoding *format_i(0b0010011, 0b010)
        asm { "slti {rd}, {rs1}, {imm}" }
        code { rd[]= (rs1.s < imm).b32  }
    }

    Instruction(:sltiu) {
        encoding *format_i(0b0010011, 0b011)
        asm { "sltiu {rd}, {rs1}, {imm}" }
        code { rd[]= (rs1.u < imm.u).b32 }
    }

    Instruction(:xori) {
        encoding *format_i(0b0010011, 0b100)
        asm { "xori {rd}, {rs1}, {imm}" }
        code { rd[]= rs1 ^ imm }
    }

    Instruction(:ori) {
        encoding *format_i(0b0010011, 0b110)
        asm { "ori {rd}, {rs1}, {imm}" }
        code { rd[]= rs1 | imm }
    }

    Instruction(:andi) {
        encoding *format_i(0b0010011, 0b111)
        asm { "andi {rd}, {rs1}, {imm}" }
        code { rd[]= rs1 & imm }
    }

    Instruction(:slli) {
        encoding *format_i_shift(0b0010011, 0b001, 0b00000)
        asm { "slli {rd}, {rs1}, {imm}" }
        code { rd[]= rs1 << imm }
    }

    Instruction(:srli) {
        encoding *format_i_shift(0b0010011, 0b101, 0b00000)
        asm { "srli {rd}, {rs1}, {imm}" }
        code { rd[]= rs1 >> imm }
    }

    Instruction(:srai) {
        encoding *format_i_shift(0b0010011, 0b101, 0b01000)
        asm { "srai {rd}, {rs1}, {imm}" }
        code { rd[]= rs1.s >> imm }
    }

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
        code { branch(select(rs1.s < rs2.s, pc + imm, pc + xlen)) }
    }

    Instruction(:bge) {
        encoding *format_b(0b1100011, 0b101)
        asm { "bge {rs1}, {rs2}, {imm}" }
        code { branch(select(rs1.s >= rs2.s, pc + imm, pc + xlen)) }
    }

    Instruction(:bltu) {
        encoding *format_b(0b1100011, 0b110)
        asm { "bltu {rs1}, {rs2}, {imm}" }
        code { branch(select(rs1.u < rs2.u, pc + imm, pc + xlen)) }
    }

    Instruction(:bgeu) {
        encoding *format_b(0b1100011, 0b111)
        asm { "bgeu {rs1}, {rs2}, {imm}" }
        code { branch(select(rs1.u >= rs2.u, pc + imm, pc + xlen)) }
    }

    Instruction(:jal) {
        encoding *format_j(0b1101111)
        asm { "jal {rd}, {imm}" }
        code { rd[]= pc + xlen; branch(pc + imm) }
    }

    Instruction(:jalr) {
        encoding *format_i(0b1100111, 0b000)
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
        encoding *format_i(0b0000011, 0b000)
        asm { "lb {rd}, {imm}({rs1})" }
        code { rd[]= mem[rs1 + imm, :b8].s32 }
    }

    Instruction(:lh) {
        encoding *format_i(0b0000011, 0b001)
        asm { "lh {rd}, {imm}({rs1})" }
        code { rd[]= mem[rs1 + imm, :b16].s32 }
    }

    Instruction(:lw) {
        encoding *format_i(0b0000011, 0b010)
        asm { "lw {rd}, {imm}({rs1})" }
        code { rd[]= mem[rs1 + imm, :b32] }
    }
    
    Instruction(:lbu) {
        encoding *format_i(0b0000011, 0b100)
        asm { "lbu {rd}, {imm}({rs1})" }
        code { rd[]= mem[rs1 + imm, :b8].u32 }
    }

    Instruction(:lhu) {
        encoding *format_i(0b0000011, 0b101)
        asm { "lhu {rd}, {imm}({rs1})" }
        code { rd[]= mem[rs1 + imm, :b16].u32 }
    }

    Instruction(:ecall) {
        encoding :E, [field(:c, 31, 0, 0b1110011)]
        asm { "ecall" }
        code { sysCall }
    }

    Instruction(:ebreak) {
        encoding :E, [field(:c, 31, 0, 0b100000000000001110011)]
        asm { "ebreak" }
        code { }
    }

    Instruction(:fence) {
        encoding :E, [field(:c1, 31, 28, 0b0000), field(:c2, 27, 24), field(:c3, 23, 20), field(:c4, 19, 0, 0b00000000000000001111)]
        asm { "fence" }
        code { }
    }
end
