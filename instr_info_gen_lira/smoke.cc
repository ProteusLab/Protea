// instr_info_gen_lira/smoke.cc
// Compile-time smoke test for the generated instruction info table; building
// this target is the test (all checks are static_asserts).

#include "instr_info.hh"

namespace ii = prot::instr_info;

static_assert(ii::kInstrDescs.size() == ii::kNumOpcodes);

// --- Control flow -------------------------------------------------------------
static_assert(ii::get(ii::Opcode::kBEQ).isBranch());
static_assert(ii::get(ii::Opcode::kBEQ).isConditionalBranch());
static_assert(ii::get(ii::Opcode::kBEQ).isTerminator());
static_assert(!ii::get(ii::Opcode::kBEQ).isCallLike());
static_assert(ii::get(ii::Opcode::kBEQ).readsPc());
static_assert(ii::get(ii::Opcode::kBEQ).writesPc());

static_assert(ii::get(ii::Opcode::kJAL).isUnconditionalBranch());
static_assert(!ii::get(ii::Opcode::kJAL).isConditionalBranch());
static_assert(ii::get(ii::Opcode::kJAL).isCallLike());
static_assert(ii::get(ii::Opcode::kJAL).writesPc());
static_assert(ii::get(ii::Opcode::kJALR).isCallLike());

// --- Memory: mayLoad/mayStore + access width ----------------------------------
static_assert(ii::get(ii::Opcode::kLW).mayLoad());
static_assert(!ii::get(ii::Opcode::kLW).mayStore());
static_assert(ii::get(ii::Opcode::kLW).mem_width == 4);
static_assert(ii::get(ii::Opcode::kSW).mayStore());
static_assert(!ii::get(ii::Opcode::kSW).mayLoad());
static_assert(ii::get(ii::Opcode::kSW).mem_width == 4);
static_assert(ii::get(ii::Opcode::kADD).mem_width == 0);

// --- Syscall ------------------------------------------------------------------
static_assert(ii::get(ii::Opcode::kECALL).isSyscall());
static_assert(ii::get(ii::Opcode::kECALL).isTerminator());

// --- Computational (ALU) + PC-relative ----------------------------------------
static_assert(ii::get(ii::Opcode::kADD).isAlu());
static_assert(!ii::get(ii::Opcode::kADD).isBranch());
static_assert(!ii::get(ii::Opcode::kADD).mayLoad());
static_assert(!ii::get(ii::Opcode::kADD).readsPc());
// auipc is computational but PC-relative (reads PC), never a control transfer.
static_assert(ii::get(ii::Opcode::kAUIPC).isAlu());
static_assert(ii::get(ii::Opcode::kAUIPC).readsPc());
static_assert(!ii::get(ii::Opcode::kAUIPC).isBranch());

// --- Operand roles (in operand_names order) -----------------------------------
// add: rs2, rs1, rd
static_assert(ii::get(ii::Opcode::kADD).operand_roles[0] == ii::Role::kSrc);
static_assert(ii::get(ii::Opcode::kADD).operand_roles[1] == ii::Role::kSrc);
static_assert(ii::get(ii::Opcode::kADD).operand_roles[2] == ii::Role::kDst);
// lw: imm, rs1, rd
static_assert(ii::get(ii::Opcode::kLW).operand_roles[0] == ii::Role::kImm);
static_assert(ii::get(ii::Opcode::kLW).operand_roles[1] == ii::Role::kSrc);
static_assert(ii::get(ii::Opcode::kLW).operand_roles[2] == ii::Role::kDst);
// auipc: rd, imm
static_assert(ii::get(ii::Opcode::kAUIPC).operand_roles[0] == ii::Role::kDst);
static_assert(ii::get(ii::Opcode::kAUIPC).operand_roles[1] == ii::Role::kImm);

// --- Extension membership (not derivable; preserved from the MRD) -------------
static_assert(ii::get(ii::Opcode::kADD).ext == "RV32I");
static_assert(ii::get(ii::Opcode::kLW).ext == "RV32I");
static_assert(ii::get(ii::Opcode::kMUL).ext == "RV32M");
static_assert(ii::get(ii::Opcode::kMUL).isAlu());

// --- Metadata -----------------------------------------------------------------
static_assert(ii::get(ii::Opcode::kADD).num_operands == 3);
static_assert(ii::get(ii::Opcode::kADD).name == "add");
static_assert(ii::get(ii::Opcode::kBEQ).operand_names[0] == "imm");

static_assert(ii::get(ii::Opcode::kLUI).const_encoding_part == 0x37);
static_assert(ii::get(ii::Opcode::kLUI).const_mask == 0x7f);
static_assert(ii::get(ii::Opcode::kLUI).encodedBytes() == 4);

int main() { return 0; }
