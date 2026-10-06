# Minimal C runtime for gem5 SE mode: main's return value is the exit code.
.globl _start
_start:
  call main
  li a7, 93
  ecall
