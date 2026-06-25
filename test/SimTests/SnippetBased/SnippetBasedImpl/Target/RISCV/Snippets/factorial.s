  addi x10, x0, 10
  jal  x1, factorial
  j end
factorial:
  addi x2, x2, -16

  sw   x1, 12(x2)
  sw   x10, 8(x2)

  addi x5, x0, 1
  ble  x10, x5, base_case
  addi x10, x10, -1
  jal  x1, factorial

  lw   x6, 8(x2)
  mul  x10, x10, x6
  jal  x0, end_factorial

base_case:
  addi x10, x0, 1

end_factorial:
  lw   x1, 12(x2)
  addi x2, x2, 16
  jalr x0, 0(x1)
end:

