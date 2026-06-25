  addi x5,  x0, 0      # x5  = fib(0)
  addi x6,  x0, 1      # x6  = fib(1)
  addi x7,  x0, 15     # x7  = n

.loop:
  beq  x7, x0, .end

  add  x28, x5, x6     # x28 = x5 + x6
  addi x5,  x6,  0     # x5 = x6
  addi x6,  x28, 0     # x6 = x28
  addi x7,  x7, -1
  jal  x0,  .loop
.end:
