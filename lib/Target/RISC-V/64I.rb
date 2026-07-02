require_relative "encoding"
require_relative "../../ADL/base"
require_relative "../../ADL/builder"

module RV64I
    include SimInfra
    extend SimInfra

    Interface {
        function :sysCall
        function :readCSR, [:b64], [:b64]
        function :writeCSR, [], [:b64, :b64]
    }

    RegisterFile(:XRegs) {
        r64  :x0, zero
        r64  :x1
        r64  :x2
        r64  :x3
        r64  :x4
        r64  :x5
        r64  :x6
        r64  :x7
        r64  :x8
        r64  :x9
        r64 :x10
        r64 :x11
        r64 :x12
        r64 :x13
        r64 :x14
        r64 :x15
        r64 :x16
        r64 :x17
        r64 :x18
        r64 :x19
        r64 :x20
        r64 :x21
        r64 :x22
        r64 :x23
        r64 :x24
        r64 :x25
        r64 :x26
        r64 :x27
        r64 :x28
        r64 :x29
        r64 :x30
        r64 :x31
        r64  :pc, pc
    }

    Instruction(:lui) {
        encoding *format_u(0b0110111)
        asm { "lui {rd}, {imm}" }
        code { rd[]= imm }
    }

    Instruction(:auipc) {
        encoding *format_u(0b0010111)
        asm { "auipc {rd}, {imm}" }
        code { rd[]= pc + imm }
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
        code { rd[]= rs1.u << (rs2.u & 63) }
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
        code { rd[]= rs1.u >> (rs2.u & 63) }
    }

    Instruction(:sra) {
        encoding *format_r(0b0110011, 0b101, 0b0100000)
        asm { "sra {rd}, {rs1}, {rs2}" }
        code { rd[]= rs1.s >> (rs2.u & 63) }
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
        code { rd[]= (rs1.s < imm.s64).b32  }
    }

    Instruction(:sltiu) {
        encoding *format_i(0b0010011, 0b011)
        asm { "sltiu {rd}, {rs1}, {imm}" }
        code { rd[]= (rs1.u < imm.u64).b32 }
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
        encoding *format_i_shift64(0b0010011, 0b001, 0b000000)
        asm { "slli {rd}, {rs1}, {imm}" }
        code { rd[]= rs1.u << imm }
    }

    Instruction(:srli) {
        encoding *format_i_shift64(0b0010011, 0b101, 0b000000)
        asm { "srli {rd}, {rs1}, {imm}" }
        code { rd[]= rs1.u >> imm }
    }

    Instruction(:srai) {
        encoding *format_i_shift64(0b0010011, 0b101, 0b010000)
        asm { "srai {rd}, {rs1}, {imm}" }
        code { rd[]= rs1.s >> imm }
    }

    Instruction(:addiw) {
        encoding *format_i(0b0011011, 0b000)
        asm { "addiw {rd}, {rs1}, {imm}" }
        code { rd[]= (rs1[31, 0] + imm).s32 }
    }

    Instruction(:slliw) {
        encoding *format_i_shiftw(0b0011011, 0b001, 0b0000000)
        asm { "slliw {rd}, {rs1}, {imm}" }
        code { rd[]= (rs1[31, 0] << imm).s32 }
    }

    Instruction(:srliw) {
        encoding *format_i_shiftw(0b0011011, 0b101, 0b0000000)
        asm { "srliw {rd}, {rs1}, {imm}" }
        code { rd[]= (rs1[31, 0] >> imm).s32 }
    }

    Instruction(:sraiw) {
        encoding *format_i_shiftw(0b0011011, 0b101, 0b0100000)
        asm { "sraiw {rd}, {rs1}, {imm}" }
        code { rd[]= (rs1[31, 0].s32 >> imm).s32 }
    }

    Instruction(:addw) {
        encoding *format_r(0b0111011, 0b000, 0b0000000)
        asm { "addw {rd}, {rs1}, {rs2}" }
        code { rd[]= (rs1[31, 0] + rs2[31, 0]).s32 }
    }

    Instruction(:subw) {
        encoding *format_r(0b0111011, 0b000, 0b0100000)
        asm { "subw {rd}, {rs1}, {rs2}" }
        code { rd[]= (rs1[31, 0] - rs2[31, 0]).s32 }
    }

    Instruction(:sllw) {
        encoding *format_r(0b0111011, 0b001, 0b0000000)
        asm { "sllw {rd}, {rs1}, {rs2}" }
        code { rd[]= (rs1[31, 0] << (rs2.u & 31)).s32 }
    }

    Instruction(:srlw) {
        encoding *format_r(0b0111011, 0b101, 0b0000000)
        asm { "srlw {rd}, {rs1}, {rs2}" }
        code { rd[]= (rs1[31, 0] >> (rs2.u & 31)).s32 }
    }

    Instruction(:sraw) {
        encoding *format_r(0b0111011, 0b101, 0b0100000)
        asm { "sraw {rd}, {rs1}, {rs2}" }
        code { rd[]= (rs1[31, 0].s32 >> (rs2.u & 31)).s32 }
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
          let :t, :b64, pc + xlen
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
        code { mem[rs1 + imm]= rs2[31, 0] }
    }

    Instruction(:sd) {
        encoding *format_s(0b0100011, 0b011)
        asm { "sd {rs2}, {imm}({rs1})" }
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
        code { rd[]= mem[rs1 + imm, :b32].s32 }
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

    Instruction(:lwu) {
        encoding *format_i(0b0000011, 0b110)
        asm { "lwu {rd}, {imm}({rs1})" }
        code { rd[]= mem[rs1 + imm, :b32].u32 }
    }

    Instruction(:ld) {
        encoding *format_i(0b0000011, 0b011)
        asm { "ld {rd}, {imm}({rs1})" }
        code { rd[]= mem[rs1 + imm, :b64] }
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

    Instruction(:fence_i) {
        encoding :E, [field(:c1, 31, 20), field(:c2, 19, 15), field(:c3, 14, 12, 0b001), field(:c4, 11, 7), field(:c5, 6, 0, 0b0001111)]
        asm { "fence.i" }
        code { }
    }

    Instruction(:csrrw) {
        encoding(*format_csr(0b1110011, 0b001))
        asm { "csrrw {rd}, {csr}, {rs1}" }
        code {
            t = readCSR(csr)
            writeCSR(csr, rs1)
            rd[] = t
        }
    }

    Instruction(:csrrs) {
        encoding(*format_csr(0b1110011, 0b010))
        asm { "csrrs {rd}, {csr}, {rs1}" }
        code {
            t = readCSR(csr)
            writeCSR(csr, t | rs1)
            rd[] = t
        }
    }

    Instruction(:csrrc) {
        encoding(*format_csr(0b1110011, 0b011))
        asm { "csrrc {rd}, {csr}, {rs1}" }
        code {
            t = readCSR(csr)
            writeCSR(csr, t & (rs1 ^ -1))
            rd[] = t
        }
    }

    Instruction(:csrrwi) {
        encoding(*format_csri(0b1110011, 0b101))
        asm { "csrrwi {rd}, {csr}, {zimm}" }
        code {
            t = readCSR(csr)
            writeCSR(csr, zimm)
            rd[] = t
        }
    }

    Instruction(:csrrsi) {
        encoding(*format_csri(0b1110011, 0b110))
        asm { "csrrsi {rd}, {csr}, {zimm}" }
        code {
            t = readCSR(csr)
            writeCSR(csr, t | zimm)
            rd[] = t
        }
    }

    Instruction(:csrrci) {
        encoding(*format_csri(0b1110011, 0b111))
        asm { "csrrci {rd}, {csr}, {zimm}" }
        code {
            t = readCSR(csr)
            writeCSR(csr, t & (zimm ^ -1))
            rd[] = t
        }
    }
end
