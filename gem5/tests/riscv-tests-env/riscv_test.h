// riscv-tests environment for gem5 SE mode (replaces env/p/riscv_test.h).
// The p environment needs CSRs, mret and tohost; here a test is a plain
// user program that reports its result through the exit syscall:
// exit code 0 on pass, the failed test number (TESTNUM) on fail.
#ifndef _ENV_GEM5_SE_H
#define _ENV_GEM5_SE_H

#define RVTEST_RV32U .macro init; .endm
#define RVTEST_RV64U RVTEST_RV32U
#define RVTEST_RV32M RVTEST_RV32U
#define RVTEST_RV64M RVTEST_RV32U

#define TESTNUM gp

#define RVTEST_CODE_BEGIN                                               \
        .text;                                                          \
        .globl _start;                                                  \
_start:                                                                 \
        li TESTNUM, 0;                                                  \
        init;

#define RVTEST_CODE_END unimp

#define RVTEST_PASS                                                     \
        li a0, 0;                                                       \
        li a7, 93;                                                      \
        ecall

// A failure before the first test case (TESTNUM == 0) exits with 255,
// so that it is never reported as a pass.
#define RVTEST_FAIL                                                     \
        mv a0, TESTNUM;                                                 \
        bnez a0, 1f;                                                    \
        li a0, 255;                                                     \
1:      li a7, 93;                                                      \
        ecall

#define EXTRA_DATA
#define RVTEST_DATA_BEGIN EXTRA_DATA .align 4; .global begin_signature; begin_signature:
#define RVTEST_DATA_END .align 4; .global end_signature; end_signature:

#endif
