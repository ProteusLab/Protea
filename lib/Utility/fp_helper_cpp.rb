module Utility
  extend Utility
  FP_INFO = {
    f32: { c_type: 'float32_t', unpack: '(uint32_t)', pack: '0xFFFFFFFF00000000ULL | (uint64_t)%s.v' },
    f64: { c_type: 'float64_t', unpack: '(uint64_t)', pack: '(uint64_t)%s.v' }
  }.freeze

  INT_INFO = {
    i32: 'int32_t',
    u32: 'uint32_t',
    i64: 'int64_t',
    u64: 'uint64_t'
  }.freeze

  def gen_typed_tmp(base, type)
    "#{base}_#{type}"
  end

  F32_MAG_MASK  = '0x7fffffffU'.freeze
  F32_SIGN_MASK = '0x80000000U'.freeze

  F64_MAG_MASK  = '0x7fffffffffffffffULL'.freeze
  F64_SIGN_MASK = '0x8000000000000000ULL'.freeze
end
