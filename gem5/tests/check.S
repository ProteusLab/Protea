# Exits with 0 on success, otherwise with the number of the failed check (t6).
.globl _start
_start:
  # 1: taken beq skips an instruction
  li   t6, 1
  li   a0, 0
  beq  x0, x0, 1f
  li   a0, 99
1:bnez a0, fail
  # 2: not-taken bne falls through
  li   t6, 2
  li   a0, 1
  bne  x0, x0, 2f
  li   a0, 0
2:bnez a0, fail
  # 3: jal/jalr link and return
  li   t6, 3
  jal  ra, func
  li   t0, 7
  bne  a1, t0, fail
  # 4: writes to x0 are dropped (j = jal x0, nop, ret above)
  li   t6, 4
  j    3f
3:addi x0, x0, 5
  bnez x0, fail
  # 5: word store/load
  li   t6, 5
  addi sp, sp, -16
  li   t0, 0x12345680
  sw   t0, 0(sp)
  lw   t1, 0(sp)
  bne  t0, t1, fail
  # 6: lb sign-extends
  li   t6, 6
  lb   t1, 0(sp)
  li   t0, -128
  bne  t0, t1, fail
  # 7: lbu zero-extends
  li   t6, 7
  lbu  t1, 0(sp)
  li   t0, 0x80
  bne  t0, t1, fail
  # 8: lh of the upper half
  li   t6, 8
  lh   t1, 2(sp)
  li   t0, 0x1234
  bne  t0, t1, fail
  # 9: sb then lw sees only the byte
  li   t6, 9
  sw   x0, 4(sp)
  sb   t1, 4(sp)
  lw   t2, 4(sp)
  li   t0, 0x34
  bne  t0, t2, fail
  # 10: store-to-load forwarding chain (O3 LSQ)
  li   t6, 10
  li   t0, 11
  sw   t0, 8(sp)
  lw   t1, 8(sp)
  addi t1, t1, 1
  sw   t1, 8(sp)
  lw   t2, 8(sp)
  li   t0, 12
  bne  t0, t2, fail
  li   t6, 0
fail:
  mv   a0, t6
  li   a7, 93
  ecall

func:
  li   a1, 7
  ret
