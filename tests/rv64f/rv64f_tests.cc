#include "decoder.hh"
#include "memory.hh"
#include "naive_interpreter.hh"

#include <array>
#include <cstdint>
#include <functional>
#include <ostream>
#include <span>
#include <string>
#include <vector>

#include <gtest/gtest.h>

extern "C" {
#include "softfloat.h"
}

namespace {

using prot::decoder::decode;
using prot::engine::Interpreter;
using prot::isa::Instruction;
using prot::isa::Opcode;
using prot::memory::makePlain;
using prot::state::CPU;

} // namespace

namespace prot::isa {
void PrintTo(Opcode opcode, std::ostream *os) {
  *os << static_cast<uint32_t>(opcode);
}
} // namespace prot::isa

namespace {

constexpr uint32_t kOpFp = 0b1010011;

uint32_t encodeR(uint32_t funct7, uint32_t rs2, uint32_t rs1, uint32_t funct3,
                 uint32_t rd, uint32_t opcode = kOpFp) {
  return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) |
         (rd << 7) | opcode;
}

uint32_t encodeR4(uint32_t funct2, uint32_t rs3, uint32_t rs2, uint32_t rs1,
                  uint32_t rm, uint32_t rd, uint32_t opcode) {
  return (rs3 << 27) | (funct2 << 25) | (rs2 << 20) | (rs1 << 15) | (rm << 12) |
         (rd << 7) | opcode;
}

uint32_t encodeI(uint32_t imm, uint32_t rs1, uint32_t funct3, uint32_t rd,
                 uint32_t opcode) {
  return ((imm & 0xfff) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) |
         opcode;
}

uint32_t encodeS(uint32_t imm, uint32_t rs2, uint32_t rs1, uint32_t funct3,
                 uint32_t opcode) {
  return (((imm >> 5) & 0x7f) << 25) | (rs2 << 20) | (rs1 << 15) |
         (funct3 << 12) | ((imm & 0x1f) << 7) | opcode;
}

uint64_t boxF32(uint32_t value) { return 0xffffffff00000000ULL | value; }

uint32_t low32(uint64_t value) { return static_cast<uint32_t>(value); }

Instruction decodeOne(uint32_t raw) {
  auto insn = decode(raw);
  EXPECT_TRUE(insn.has_value()) << "raw instruction: 0x" << std::hex << raw;
  return *insn;
}

void expectDecode(uint32_t raw, Opcode opcode) {
  const auto insn = decodeOne(raw);
  EXPECT_EQ(insn.m_opc, opcode);
}

void expectDecodeOperands(uint32_t raw, Opcode opcode,
                          std::span<const uint64_t> operands) {
  const auto insn = decodeOne(raw);
  EXPECT_EQ(insn.m_opc, opcode);
  const std::array actual{insn.operand0, insn.operand1, insn.operand2,
                          insn.operand3};
  for (std::size_t i = 0; i < operands.size(); ++i) {
    EXPECT_EQ(actual[i], operands[i]) << "operand" << i;
  }
}

Instruction decodeAndExecute(CPU &cpu, uint32_t raw) {
  auto insn = decodeOne(raw);
  Interpreter interpreter;
  interpreter.execute(cpu, insn);
  return insn;
}

void withSoftfloatRounding(uint_fast8_t rm, const std::function<void()> &body) {
  const auto saved = softfloat_roundingMode;
  softfloat_roundingMode = rm;
  body();
  softfloat_roundingMode = saved;
}

struct RoundingOpcodes {
  std::array<Opcode, 5> opcodes;
};

constexpr std::array<uint32_t, 5> kRoundingModes{0, 1, 2, 3, 4};

void expectRoundedRFamily(uint32_t funct7, const RoundingOpcodes &ops) {
  for (std::size_t i = 0; i < kRoundingModes.size(); ++i) {
    expectDecode(encodeR(funct7, 3, 2, kRoundingModes[i], 1), ops.opcodes[i]);
  }
}

void expectRoundedR4Family(uint32_t opcode, uint32_t funct2,
                           const RoundingOpcodes &ops) {
  for (std::size_t i = 0; i < kRoundingModes.size(); ++i) {
    expectDecode(encodeR4(funct2, 4, 3, 2, kRoundingModes[i], 1, opcode),
                 ops.opcodes[i]);
  }
}

void expectRoundedFcvtToXFamily(uint32_t funct7, uint32_t rs2,
                                const RoundingOpcodes &ops) {
  for (std::size_t i = 0; i < kRoundingModes.size(); ++i) {
    expectDecode(encodeR(funct7, rs2, 2, kRoundingModes[i], 1), ops.opcodes[i]);
  }
}

void expectRoundedFcvtToFFamily(uint32_t funct7, uint32_t rs2,
                                const RoundingOpcodes &ops) {
  for (std::size_t i = 0; i < kRoundingModes.size(); ++i) {
    expectDecode(encodeR(funct7, rs2, 2, kRoundingModes[i], 1), ops.opcodes[i]);
  }
}

TEST(RV64FDecodeTest, DecodesAllRoundedArithmeticOpcodes) {
  expectRoundedRFamily(0b0000000, {{{Opcode::kFADD_S_RNE, Opcode::kFADD_S_RTZ,
                                     Opcode::kFADD_S_RDN, Opcode::kFADD_S_RUP,
                                     Opcode::kFADD_S_RMM}}});
  expectRoundedRFamily(0b0000001, {{{Opcode::kFADD_D_RNE, Opcode::kFADD_D_RTZ,
                                     Opcode::kFADD_D_RDN, Opcode::kFADD_D_RUP,
                                     Opcode::kFADD_D_RMM}}});
  expectRoundedRFamily(0b0000100, {{{Opcode::kFSUB_S_RNE, Opcode::kFSUB_S_RTZ,
                                     Opcode::kFSUB_S_RDN, Opcode::kFSUB_S_RUP,
                                     Opcode::kFSUB_S_RMM}}});
  expectRoundedRFamily(0b0000101, {{{Opcode::kFSUB_D_RNE, Opcode::kFSUB_D_RTZ,
                                     Opcode::kFSUB_D_RDN, Opcode::kFSUB_D_RUP,
                                     Opcode::kFSUB_D_RMM}}});
  expectRoundedRFamily(0b0001000, {{{Opcode::kFMUL_S_RNE, Opcode::kFMUL_S_RTZ,
                                     Opcode::kFMUL_S_RDN, Opcode::kFMUL_S_RUP,
                                     Opcode::kFMUL_S_RMM}}});
  expectRoundedRFamily(0b0001001, {{{Opcode::kFMUL_D_RNE, Opcode::kFMUL_D_RTZ,
                                     Opcode::kFMUL_D_RDN, Opcode::kFMUL_D_RUP,
                                     Opcode::kFMUL_D_RMM}}});
  expectRoundedRFamily(0b0001100, {{{Opcode::kFDIV_S_RNE, Opcode::kFDIV_S_RTZ,
                                     Opcode::kFDIV_S_RDN, Opcode::kFDIV_S_RUP,
                                     Opcode::kFDIV_S_RMM}}});
  expectRoundedRFamily(0b0001101, {{{Opcode::kFDIV_D_RNE, Opcode::kFDIV_D_RTZ,
                                     Opcode::kFDIV_D_RDN, Opcode::kFDIV_D_RUP,
                                     Opcode::kFDIV_D_RMM}}});
  expectRoundedRFamily(0b0101100, {{{Opcode::kFSQRT_S_RNE, Opcode::kFSQRT_S_RTZ,
                                     Opcode::kFSQRT_S_RDN, Opcode::kFSQRT_S_RUP,
                                     Opcode::kFSQRT_S_RMM}}});
  expectRoundedRFamily(0b0101101, {{{Opcode::kFSQRT_D_RNE, Opcode::kFSQRT_D_RTZ,
                                     Opcode::kFSQRT_D_RDN, Opcode::kFSQRT_D_RUP,
                                     Opcode::kFSQRT_D_RMM}}});
}

TEST(RV64FDecodeTest, DecodesAllFusedMultiplyAddOpcodes) {
  expectRoundedR4Family(
      0b1000011, 0b00,
      {{{Opcode::kFMADD_S_RNE, Opcode::kFMADD_S_RTZ, Opcode::kFMADD_S_RDN,
         Opcode::kFMADD_S_RUP, Opcode::kFMADD_S_RMM}}});
  expectRoundedR4Family(
      0b1000011, 0b01,
      {{{Opcode::kFMADD_D_RNE, Opcode::kFMADD_D_RTZ, Opcode::kFMADD_D_RDN,
         Opcode::kFMADD_D_RUP, Opcode::kFMADD_D_RMM}}});
  expectRoundedR4Family(
      0b1000111, 0b00,
      {{{Opcode::kFMSUB_S_RNE, Opcode::kFMSUB_S_RTZ, Opcode::kFMSUB_S_RDN,
         Opcode::kFMSUB_S_RUP, Opcode::kFMSUB_S_RMM}}});
  expectRoundedR4Family(
      0b1000111, 0b01,
      {{{Opcode::kFMSUB_D_RNE, Opcode::kFMSUB_D_RTZ, Opcode::kFMSUB_D_RDN,
         Opcode::kFMSUB_D_RUP, Opcode::kFMSUB_D_RMM}}});
  expectRoundedR4Family(
      0b1001111, 0b00,
      {{{Opcode::kFNMADD_S_RNE, Opcode::kFNMADD_S_RTZ, Opcode::kFNMADD_S_RDN,
         Opcode::kFNMADD_S_RUP, Opcode::kFNMADD_S_RMM}}});
  expectRoundedR4Family(
      0b1001111, 0b01,
      {{{Opcode::kFNMADD_D_RNE, Opcode::kFNMADD_D_RTZ, Opcode::kFNMADD_D_RDN,
         Opcode::kFNMADD_D_RUP, Opcode::kFNMADD_D_RMM}}});
  expectRoundedR4Family(
      0b1001011, 0b00,
      {{{Opcode::kFNMSUB_S_RNE, Opcode::kFNMSUB_S_RTZ, Opcode::kFNMSUB_S_RDN,
         Opcode::kFNMSUB_S_RUP, Opcode::kFNMSUB_S_RMM}}});
  expectRoundedR4Family(
      0b1001011, 0b01,
      {{{Opcode::kFNMSUB_D_RNE, Opcode::kFNMSUB_D_RTZ, Opcode::kFNMSUB_D_RDN,
         Opcode::kFNMSUB_D_RUP, Opcode::kFNMSUB_D_RMM}}});
}

TEST(RV64FDecodeTest, DecodesMemoryAndNonRoundedOpcodes) {
  expectDecode(encodeI(0x10, 2, 0b010, 1, 0b0000111), Opcode::kFLW);
  expectDecode(encodeI(0x10, 2, 0b011, 1, 0b0000111), Opcode::kFLD);
  expectDecode(encodeS(0x10, 3, 2, 0b010, 0b0100111), Opcode::kFSW);
  expectDecode(encodeS(0x10, 3, 2, 0b011, 0b0100111), Opcode::kFSD);

  expectDecode(encodeR(0b0010000, 3, 2, 0b000, 1), Opcode::kFSGNJ_S);
  expectDecode(encodeR(0b0010001, 3, 2, 0b000, 1), Opcode::kFSGNJ_D);
  expectDecode(encodeR(0b0010000, 3, 2, 0b001, 1), Opcode::kFSGNJN_S);
  expectDecode(encodeR(0b0010001, 3, 2, 0b001, 1), Opcode::kFSGNJN_D);
  expectDecode(encodeR(0b0010000, 3, 2, 0b010, 1), Opcode::kFSGNJX_S);
  expectDecode(encodeR(0b0010001, 3, 2, 0b010, 1), Opcode::kFSGNJX_D);

  expectDecode(encodeR(0b0010100, 3, 2, 0b000, 1), Opcode::kFMIN_S);
  expectDecode(encodeR(0b0010101, 3, 2, 0b000, 1), Opcode::kFMIN_D);
  expectDecode(encodeR(0b0010100, 3, 2, 0b001, 1), Opcode::kFMAX_S);
  expectDecode(encodeR(0b0010101, 3, 2, 0b001, 1), Opcode::kFMAX_D);

  expectDecode(encodeR(0b1010000, 3, 2, 0b010, 1), Opcode::kFEQ_S);
  expectDecode(encodeR(0b1010001, 3, 2, 0b010, 1), Opcode::kFEQ_D);
  expectDecode(encodeR(0b1010000, 3, 2, 0b001, 1), Opcode::kFLT_S);
  expectDecode(encodeR(0b1010001, 3, 2, 0b001, 1), Opcode::kFLT_D);
  expectDecode(encodeR(0b1010000, 3, 2, 0b000, 1), Opcode::kFLE_S);
  expectDecode(encodeR(0b1010001, 3, 2, 0b000, 1), Opcode::kFLE_D);

  expectDecode(encodeR(0b1110000, 0, 2, 0b001, 1), Opcode::kFCLASS_S);
  expectDecode(encodeR(0b1110001, 0, 2, 0b001, 1), Opcode::kFCLASS_D);
  expectDecode(encodeR(0b1110000, 0, 2, 0b000, 1), Opcode::kFMV_X_W);
  expectDecode(encodeR(0b1111000, 0, 2, 0b000, 1), Opcode::kFMV_W_X);
}

TEST(RV64FDecodeTest, DecodesAllConversionOpcodes) {
  expectRoundedFcvtToXFamily(
      0b1100000, 0b00000,
      {{{Opcode::kFCVT_W_S_RNE, Opcode::kFCVT_W_S_RTZ, Opcode::kFCVT_W_S_RDN,
         Opcode::kFCVT_W_S_RUP, Opcode::kFCVT_W_S_RMM}}});
  expectRoundedFcvtToXFamily(
      0b1100000, 0b00001,
      {{{Opcode::kFCVT_WU_S_RNE, Opcode::kFCVT_WU_S_RTZ, Opcode::kFCVT_WU_S_RDN,
         Opcode::kFCVT_WU_S_RUP, Opcode::kFCVT_WU_S_RMM}}});
  expectRoundedFcvtToXFamily(
      0b1100000, 0b00010,
      {{{Opcode::kFCVT_L_S_RNE, Opcode::kFCVT_L_S_RTZ, Opcode::kFCVT_L_S_RDN,
         Opcode::kFCVT_L_S_RUP, Opcode::kFCVT_L_S_RMM}}});
  expectRoundedFcvtToXFamily(
      0b1100000, 0b00011,
      {{{Opcode::kFCVT_LU_S_RNE, Opcode::kFCVT_LU_S_RTZ, Opcode::kFCVT_LU_S_RDN,
         Opcode::kFCVT_LU_S_RUP, Opcode::kFCVT_LU_S_RMM}}});
  expectRoundedFcvtToFFamily(
      0b1101000, 0b00000,
      {{{Opcode::kFCVT_S_W_RNE, Opcode::kFCVT_S_W_RTZ, Opcode::kFCVT_S_W_RDN,
         Opcode::kFCVT_S_W_RUP, Opcode::kFCVT_S_W_RMM}}});
  expectRoundedFcvtToFFamily(
      0b1101000, 0b00001,
      {{{Opcode::kFCVT_S_WU_RNE, Opcode::kFCVT_S_WU_RTZ, Opcode::kFCVT_S_WU_RDN,
         Opcode::kFCVT_S_WU_RUP, Opcode::kFCVT_S_WU_RMM}}});
  expectRoundedFcvtToFFamily(
      0b1101000, 0b00010,
      {{{Opcode::kFCVT_S_L_RNE, Opcode::kFCVT_S_L_RTZ, Opcode::kFCVT_S_L_RDN,
         Opcode::kFCVT_S_L_RUP, Opcode::kFCVT_S_L_RMM}}});
  expectRoundedFcvtToFFamily(
      0b1101000, 0b00011,
      {{{Opcode::kFCVT_S_LU_RNE, Opcode::kFCVT_S_LU_RTZ, Opcode::kFCVT_S_LU_RDN,
         Opcode::kFCVT_S_LU_RUP, Opcode::kFCVT_S_LU_RMM}}});
}

TEST(RV64FDecodeTest, DecodesExpectedOperandOrderForRepresentativeFormats) {
  expectDecodeOperands(encodeR(0b0000000, 3, 2, 0, 1), Opcode::kFADD_S_RNE,
                       std::array<uint64_t, 3>{3, 2, 1});
  expectDecodeOperands(encodeR4(0, 4, 3, 2, 0, 1, 0b1000011),
                       Opcode::kFMADD_S_RNE,
                       std::array<uint64_t, 4>{4, 3, 2, 1});
  expectDecodeOperands(encodeI(0x10, 2, 0b010, 1, 0b0000111), Opcode::kFLW,
                       std::array<uint64_t, 3>{0x10, 2, 1});
  expectDecodeOperands(encodeS(0x10, 3, 2, 0b010, 0b0100111), Opcode::kFSW,
                       std::array<uint64_t, 3>{0x10, 2, 3});
}

TEST(RV64FExecutionTest, ExecutesSingleAndDoubleArithmetic) {
  auto memory = makePlain(256);
  CPU cpu(memory.get());
  cpu.setFRegs(2, boxF32(0x3fc00000)); // 1.5f
  cpu.setFRegs(3, boxF32(0x40100000)); // 2.25f

  withSoftfloatRounding(softfloat_round_near_even, [&] {
    const float32_t lhs{0x3fc00000};
    const float32_t rhs{0x40100000};
    decodeAndExecute(cpu, encodeR(0b0000000, 3, 2, 0, 1));
    EXPECT_EQ(cpu.getFRegs<uint64_t>(1), boxF32(f32_add(lhs, rhs).v));
    decodeAndExecute(cpu, encodeR(0b0000100, 3, 2, 0, 1));
    EXPECT_EQ(cpu.getFRegs<uint64_t>(1), boxF32(f32_sub(lhs, rhs).v));
    decodeAndExecute(cpu, encodeR(0b0001000, 3, 2, 0, 1));
    EXPECT_EQ(cpu.getFRegs<uint64_t>(1), boxF32(f32_mul(lhs, rhs).v));
    decodeAndExecute(cpu, encodeR(0b0001100, 3, 2, 0, 1));
    EXPECT_EQ(cpu.getFRegs<uint64_t>(1), boxF32(f32_div(lhs, rhs).v));
    decodeAndExecute(cpu, encodeR(0b0101100, 0, 3, 0, 1));
    EXPECT_EQ(cpu.getFRegs<uint64_t>(1), boxF32(f32_sqrt(rhs).v));
  });

  cpu.setFRegs(2, 0x3ff8000000000000ULL); // 1.5
  cpu.setFRegs(3, 0x4002000000000000ULL); // 2.25

  withSoftfloatRounding(softfloat_round_near_even, [&] {
    const float64_t lhs{0x3ff8000000000000ULL};
    const float64_t rhs{0x4002000000000000ULL};
    decodeAndExecute(cpu, encodeR(0b0000001, 3, 2, 0, 1));
    EXPECT_EQ(cpu.getFRegs<uint64_t>(1), f64_add(lhs, rhs).v);
    decodeAndExecute(cpu, encodeR(0b0000101, 3, 2, 0, 1));
    EXPECT_EQ(cpu.getFRegs<uint64_t>(1), f64_sub(lhs, rhs).v);
    decodeAndExecute(cpu, encodeR(0b0001001, 3, 2, 0, 1));
    EXPECT_EQ(cpu.getFRegs<uint64_t>(1), f64_mul(lhs, rhs).v);
    decodeAndExecute(cpu, encodeR(0b0001101, 3, 2, 0, 1));
    EXPECT_EQ(cpu.getFRegs<uint64_t>(1), f64_div(lhs, rhs).v);
    decodeAndExecute(cpu, encodeR(0b0101101, 0, 3, 0, 1));
    EXPECT_EQ(cpu.getFRegs<uint64_t>(1), f64_sqrt(rhs).v);
  });
}

TEST(RV64FExecutionTest, ExecutesMemorySignCompareClassAndMoveInstructions) {
  auto memory = makePlain(256);
  CPU cpu(memory.get());
  cpu.setXRegs(2, 64U);
  memory->write<uint32_t>(68, 0x3f800000U);
  memory->write<uint64_t>(80, 0x4000000000000000ULL);

  decodeAndExecute(cpu, encodeI(4, 2, 0b010, 1, 0b0000111));
  EXPECT_EQ(low32(cpu.getFRegs<uint64_t>(1)), 0x3f800000U);

  decodeAndExecute(cpu, encodeI(16, 2, 0b011, 1, 0b0000111));
  EXPECT_EQ(cpu.getFRegs<uint64_t>(1), 0x4000000000000000ULL);

  cpu.setFRegs(3, boxF32(0x40400000));
  decodeAndExecute(cpu, encodeS(24, 3, 2, 0b010, 0b0100111));
  EXPECT_EQ(memory->read<uint32_t>(88), 0x40400000U);

  cpu.setFRegs(3, 0x4008000000000000ULL);
  decodeAndExecute(cpu, encodeS(32, 3, 2, 0b011, 0b0100111));
  EXPECT_EQ(memory->read<uint64_t>(96), 0x4008000000000000ULL);

  cpu.setFRegs(2, boxF32(0x3f800000));
  cpu.setFRegs(3, boxF32(0x80000000));
  decodeAndExecute(cpu, encodeR(0b0010000, 3, 2, 0b000, 1));
  EXPECT_EQ(cpu.getFRegs<uint64_t>(1), boxF32(0xbf800000));
  decodeAndExecute(cpu, encodeR(0b0010000, 3, 2, 0b001, 1));
  EXPECT_EQ(cpu.getFRegs<uint64_t>(1), boxF32(0x3f800000));
  decodeAndExecute(cpu, encodeR(0b0010000, 3, 2, 0b010, 1));
  EXPECT_EQ(cpu.getFRegs<uint64_t>(1), boxF32(0xbf800000));

  cpu.setFRegs(2, boxF32(0x3f800000));
  cpu.setFRegs(3, boxF32(0x40000000));
  decodeAndExecute(cpu, encodeR(0b0010100, 3, 2, 0b000, 1));
  EXPECT_EQ(cpu.getFRegs<uint64_t>(1), boxF32(0x3f800000));
  decodeAndExecute(cpu, encodeR(0b0010100, 3, 2, 0b001, 1));
  EXPECT_EQ(cpu.getFRegs<uint64_t>(1), boxF32(0x40000000));
  decodeAndExecute(cpu, encodeR(0b1010000, 3, 2, 0b010, 1));
  EXPECT_EQ(cpu.getXRegs<uint32_t>(1), 0U);
  decodeAndExecute(cpu, encodeR(0b1010000, 3, 2, 0b001, 1));
  EXPECT_EQ(cpu.getXRegs<uint32_t>(1), 1U);
  decodeAndExecute(cpu, encodeR(0b1010000, 3, 2, 0b000, 1));
  EXPECT_EQ(cpu.getXRegs<uint32_t>(1), 1U);

  decodeAndExecute(cpu, encodeR(0b1110000, 0, 2, 0b001, 1));
  EXPECT_EQ(cpu.getXRegs<uint32_t>(1), 1U << 6);
  cpu.setFRegs(2, 0x7ff8000000000000ULL);
  decodeAndExecute(cpu, encodeR(0b1110001, 0, 2, 0b001, 1));
  EXPECT_EQ(cpu.getXRegs<uint32_t>(1), 1U << 9);

  cpu.setFRegs(2, boxF32(0xdeadbeef));
  decodeAndExecute(cpu, encodeR(0b1110000, 0, 2, 0b000, 1));
  EXPECT_EQ(cpu.getXRegs<uint32_t>(1), 0xdeadbeefU);

  cpu.setXRegs(2, 0x3f800000U);
  decodeAndExecute(cpu, encodeR(0b1111000, 0, 2, 0b000, 1));
  EXPECT_EQ(low32(cpu.getFRegs<uint64_t>(1)), 0x3f800000U);
}

TEST(RV64FExecutionTest, ExecutesConversionsRepresentableByCurrentXRegWidth) {
  auto memory = makePlain(256);
  CPU cpu(memory.get());

  cpu.setFRegs(2, boxF32(0x40200000)); // 2.5f
  decodeAndExecute(cpu, encodeR(0b1100000, 0b00000, 2, 0b001, 1));
  EXPECT_EQ(cpu.getXRegs<uint32_t>(1), 2U);
  decodeAndExecute(cpu, encodeR(0b1100000, 0b00001, 2, 0b001, 1));
  EXPECT_EQ(cpu.getXRegs<uint32_t>(1), 2U);
  decodeAndExecute(cpu, encodeR(0b1100000, 0b00010, 2, 0b001, 1));
  EXPECT_EQ(cpu.getXRegs<uint32_t>(1), 2U);
  decodeAndExecute(cpu, encodeR(0b1100000, 0b00011, 2, 0b001, 1));
  EXPECT_EQ(cpu.getXRegs<uint32_t>(1), 2U);

  cpu.setXRegs(2, 3U);
  decodeAndExecute(cpu, encodeR(0b1101000, 0b00000, 2, 0b000, 1));
  EXPECT_EQ(low32(cpu.getFRegs<uint64_t>(1)), 0x40400000U);
  decodeAndExecute(cpu, encodeR(0b1101000, 0b00001, 2, 0b000, 1));
  EXPECT_EQ(low32(cpu.getFRegs<uint64_t>(1)), 0x40400000U);
  decodeAndExecute(cpu, encodeR(0b1101000, 0b00010, 2, 0b000, 1));
  EXPECT_EQ(low32(cpu.getFRegs<uint64_t>(1)), 0x40400000U);
  decodeAndExecute(cpu, encodeR(0b1101000, 0b00011, 2, 0b000, 1));
  EXPECT_EQ(low32(cpu.getFRegs<uint64_t>(1)), 0x40400000U);
}

} // namespace
