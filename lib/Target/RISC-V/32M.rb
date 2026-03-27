require_relative "encoding"
require_relative "../../ADL/base"
require_relative "../../ADL/builder"

module RV32M
    include SimInfra
    extend SimInfra

    Instruction(:mul) {
        encoding *format_r(0b0110011, 0b000, 0b0000001)
        asm { "mul {rd}, {rs1}, {rs2}" }
        code { rd[]= rs1.s * rs2.s }
    }

    Instruction(:mulh) {
        encoding *format_r(0b0110011, 0b001, 0b0000001)
        asm { "mulh {rd}, {rs1}, {rs2}" }
        code { rd[]= (rs1.s64 * rs2.s64) >> 32 }
    }

    Instruction(:mulhsu) {
        encoding *format_r(0b0110011, 0b010, 0b0000001)
        asm { "mulhsu {rd}, {rs1}, {rs2}" }
        code { rd[]= (rs1.s64 * rs2.u64.s64) >> 32 }
    }

    Instruction(:mulhu) {
        encoding *format_r(0b0110011, 0b011, 0b0000001)
        asm { "mulhu {rd}, {rs1}, {rs2}" }
        code { rd[]= (rs1.u64 * rs2.u64) >> 32 }
    }

    Instruction(:div) {
        encoding *format_r(0b0110011, 0b100, 0b0000001)
        asm { "div {rd}, {rs1}, {rs2}" }
        code { rd[]= rs1.s / rs2.s }
    }

    Instruction(:divu) {
        encoding *format_r(0b0110011, 0b101, 0b0000001)
        asm { "divu {rd}, {rs1}, {rs2}" }
        code { rd[]= rs1.u / rs2.u }
    }
    
    Instruction(:rem) {
        encoding *format_r(0b0110011, 0b110, 0b0000001)
        asm { "rem {rd}, {rs1}, {rs2}" }
        code { rd[]= rs1.s % rs2.s }
    }

    Instruction(:remu) {
        encoding *format_r(0b0110011, 0b111, 0b0000001)
        asm { "remu {rd}, {rs1}, {rs2}" }
        code { rd[]= rs1.u % rs2.u }
    }
end
