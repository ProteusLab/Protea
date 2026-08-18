module SimInfra
  # Floating point DSL operations, mixed into Scope.
  # Relies on Scope#binOp/#unOp/#ternOp for IR emission, so it is not
  # usable on its own.
  module FloatingPointOps
    # Floating point Arithmetic
    def f32_add(a, b, rm = nil) = binOp(a, b, :f32_add, rm)
    def f64_add(a, b, rm = nil) = binOp(a, b, :f64_add, rm)
    def f32_sub(a, b, rm = nil) = binOp(a, b, :f32_sub, rm)
    def f64_sub(a, b, rm = nil) = binOp(a, b, :f64_sub, rm)
    def f32_mul(a, b, rm = nil) = binOp(a, b, :f32_mul, rm)
    def f64_mul(a, b, rm = nil) = binOp(a, b, :f64_mul, rm)
    def f32_div(a, b, rm = nil) = binOp(a, b, :f32_div, rm)
    def f64_div(a, b, rm = nil) = binOp(a, b, :f64_div, rm)

    def f32_sqrt(a, rm = nil) = unOp(a, :f32_sqrt, rm)
    def f64_sqrt(a, rm = nil) = unOp(a, :f64_sqrt, rm)

    def f32_mul_add(a, b, c, rm = nil)   = ternOp(a, b, c, :f32_mul_add, rm)
    def f64_mul_add(a, b, c, rm = nil)   = ternOp(a, b, c, :f64_mul_add, rm)
    def f32_mul_sub(a, b, c, rm = nil)   = ternOp(a, b, c, :f32_mul_sub, rm)
    def f64_mul_sub(a, b, c, rm = nil)   = ternOp(a, b, c, :f64_mul_sub, rm)
    def f32_mul_add_n(a, b, c, rm = nil) = ternOp(a, b, c, :f32_mul_add_n, rm)
    def f64_mul_add_n(a, b, c, rm = nil) = ternOp(a, b, c, :f64_mul_add_n, rm)
    def f32_mul_sub_n(a, b, c, rm = nil) = ternOp(a, b, c, :f32_mul_sub_n, rm)
    def f64_mul_sub_n(a, b, c, rm = nil) = ternOp(a, b, c, :f64_mul_sub_n, rm)

    # Minmax, sign injection
    def f32_min(a, b) = binOp(a, b, :f32_min)
    def f64_min(a, b) = binOp(a, b, :f64_min)
    def f32_max(a, b) = binOp(a, b, :f32_max)
    def f64_max(a, b) = binOp(a, b, :f64_max)
    def f32_eq(a, b)  = binOp(a, b, :f32_eq)
    def f64_eq(a, b)  = binOp(a, b, :f64_eq)
    def f32_lt(a, b)  = binOp(a, b, :f32_lt)
    def f64_lt(a, b)  = binOp(a, b, :f64_lt)
    def f32_le(a, b)  = binOp(a, b, :f32_le)
    def f64_le(a, b)  = binOp(a, b, :f64_le)
    def f32_sign_injection(a, b) = binOp(a, b, :f32_sign_injection)
    def f64_sign_injection(a, b) = binOp(a, b, :f64_sign_injection)
    def f32_sign_injection_n(a, b) = binOp(a, b, :f32_sign_injection_n)
    def f64_sign_injection_n(a, b) = binOp(a, b, :f64_sign_injection_n)
    def f32_sign_xor(a, b) = binOp(a, b, :f32_sign_xor)
    def f64_sign_xor(a, b) = binOp(a, b, :f64_sign_xor)

    # Conversion
    def f32_to_i32(a, rm = nil) = unOp(a, :f32_to_i32, rm)
    def f32_to_u32(a, rm = nil) = unOp(a, :f32_to_u32, rm)
    def f32_to_i64(a, rm = nil) = unOp(a, :f32_to_i64, rm)
    def f32_to_u64(a, rm = nil) = unOp(a, :f32_to_u64, rm)
    def i32_to_f32(a, rm = nil) = unOp(a, :i32_to_f32, rm)
    def u32_to_f32(a, rm = nil) = unOp(a, :u32_to_f32, rm)
    def i64_to_f32(a, rm = nil) = unOp(a, :i64_to_f32, rm)
    def u64_to_f32(a, rm = nil) = unOp(a, :u64_to_f32, rm)

    # Classification
    def f32_classify(a) = unOp(a, :f32_classify)
    def f64_classify(a) = unOp(a, :f64_classify)
  end
end
