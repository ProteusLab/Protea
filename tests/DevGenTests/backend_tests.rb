# frozen_string_literal: true

require_relative '../helper'

class DevGenBackendTests < Protea::DevGenTestCase
  def test_new_var
    desc = { name: :new_var, oprnds: [{ name: :x, type: :b32, regset: nil }], attrs: nil }
    assert_equal 'uint32_t x;', DevGen.gen_stmt(desc)
  end

  def test_new_var_b8
    desc = { name: :new_var, oprnds: [{ name: :x, type: :b8, regset: nil }], attrs: nil }
    assert_equal 'uint8_t x;', DevGen.gen_stmt(desc)
  end

  def test_new_var_tmp_is_elided
    desc = { name: :new_var, oprnds: [{ name: :_tmp0, type: :b32, regset: nil }], attrs: nil }
    assert_equal '', DevGen.gen_stmt(desc)
  end

  def test_let_to_var
    desc = { name: :let,
             oprnds: [{ name: :y, type: :b32, regset: nil },
                      { name: :x, type: :b32, regset: nil }],
             attrs: nil }
    assert_equal 'y = x;', DevGen.gen_stmt(desc)
  end

  def test_let_to_tmp_populates_tmphash
    desc = { name: :let,
             oprnds: [{ name: :_tmp0, type: :b32, regset: nil },
                      { name: :x, type: :b32, regset: nil }],
             attrs: nil }
    assert_equal '', DevGen.gen_stmt(desc)
    assert_equal :x, devgen_tmphash[:_tmp0]
  end

  def test_let_to_regfield_inserts
    setup_devgen(devdesc: { registers: { r: { fields: { a: { lsb: 0, size: 1 } } } } },
                 self_name: :r)
    desc = { name: :let,
             oprnds: [{ name: :a, type: :rf1, regset: nil },
                      { name: nil, type: :iconst, value: 1 }],
             attrs: nil }
    assert_equal 'protea::_insert(r, 0, 1, 1);', DevGen.gen_stmt(desc)
  end

  def test_let_to_regfield_nonzero_lsb
    setup_devgen(devdesc: { registers: { r: { fields: { a: { lsb: 4, size: 2 } } } } },
                 self_name: :r)
    desc = { name: :let,
             oprnds: [{ name: :a, type: :rf2, regset: nil },
                      { name: nil, type: :iconst, value: 3 }],
             attrs: nil }
    assert_equal 'protea::_insert(r, 4, 2, 3);', DevGen.gen_stmt(desc)
  end

  def test_let_to_rf_tmp_is_elided
    setup_devgen(devdesc: { registers: {} }, self_name: :r)
    desc = { name: :let,
             oprnds: [{ name: :_tmp0, type: :rf1, regset: nil },
                      { name: nil, type: :iconst, value: 0 }],
             attrs: nil }
    assert_equal '', DevGen.gen_stmt(desc)
    assert_equal 0, devgen_tmphash[:_tmp0]
  end

  def test_if_scope
    setup_devgen(self_name: :r)
    cond = { name: :x, type: :b1, regset: nil }
    body = { tree: [{ name: :let,
                      oprnds: [{ name: :y, type: :b32, regset: nil },
                               { name: nil, type: :iconst, value: 1 }],
                      attrs: nil }] }
    desc = { name: :if, oprnds: [cond, body], attrs: nil }
    assert_equal "if (x) {\n    y = 1;\n}", DevGen.gen_stmt(desc)
  end

  def test_return_void
    desc = { name: :ret, oprnds: [], attrs: nil }
    assert_equal 'return;', DevGen.gen_stmt(desc)
  end

  def test_return_value
    desc = { name: :ret, oprnds: [{ name: :x, type: :b32, regset: nil }], attrs: nil }
    assert_equal 'return x;', DevGen.gen_stmt(desc)
  end

  def test_get_reg_field
    setup_devgen(devdesc: { registers: { r: { fields: { a: { lsb: 4, size: 2 } } } } },
                 self_name: :r)
    desc = { name: :get_reg_field,
             oprnds: [{ name: :t, type: :rf2, regset: nil },
                      { name: :r, type: :"D::r_seq", regset: nil },
                      :a],
             attrs: nil }
    assert_equal 't = protea::_extract(r, 4, 2);', DevGen.gen_stmt(desc)
  end

  def test_call
    desc = { name: :call,
             oprnds: [{ name: :ret, type: :b32, regset: nil },
                      :foo,
                      { name: :a, type: :b32, regset: nil }],
             attrs: nil }
    assert_equal 'ret = foo(a);', DevGen.gen_stmt(desc)
  end

  def test_voidcall
    desc = { name: :voidcall,
             oprnds: [:foo, { name: :a, type: :b32, regset: nil }],
             attrs: nil }
    assert_equal 'foo(a);', DevGen.gen_stmt(desc)
  end

  def test_membercall_at_into_tmphash
    setup_devgen(self_name: :r)
    desc = { name: :membercall,
             oprnds: [{ name: :_tmp0, type: :b32, regset: nil },
                      { name: :arr, type: :b32, regset: nil },
                      :at,
                      { name: :i, type: :b32, regset: nil }],
             attrs: nil }
    assert_equal '', DevGen.gen_stmt(desc)
    assert_equal 'arr[i]', devgen_tmphash[:_tmp0]
  end

  def test_binop_add_into_tmphash
    setup_devgen(self_name: :r)
    desc = { name: :add,
             oprnds: [{ name: :_tmp0, type: :b32, regset: nil },
                      { name: :x, type: :b32, regset: nil },
                      { name: nil, type: :iconst, value: 1 }],
             attrs: nil }
    assert_equal '', DevGen.gen_stmt(desc)
    assert_equal 'protea::_add(x, 1)', devgen_tmphash[:_tmp0]
  end

  def test_gen_cpp_type_bitvectors
    assert_equal :uint8_t, DevGen.gen_cpp_type(:b8)
    assert_equal :uint32_t, DevGen.gen_cpp_type(:b32)
    assert_equal :uint64_t, DevGen.gen_cpp_type(:b33)
    assert_equal :uint64_t, DevGen.gen_cpp_type(:b64)
    assert_equal :uint8_t, DevGen.gen_cpp_type(:rf1)
  end

  def test_gen_cpp_type_ptr_and_ref
    assert_equal 'int*', DevGen.gen_cpp_type(:"ptr(int)")
    assert_equal 'int&', DevGen.gen_cpp_type(:"ref(int)")
  end

  def test_gen_op_iconst
    setup_devgen(self_name: :r)
    assert_equal 42, DevGen.gen_op({ type: :iconst, value: 42 })
    assert_equal '"hi"', DevGen.gen_op({ type: :iconst, value: 'hi' })
  end

  def test_gen_op_names
    setup_devgen(self_name: :r)
    assert_equal :r, DevGen.gen_op({ name: :self, type: :b8 })
    assert_equal :x, DevGen.gen_op({ name: :x, type: :b32 })
  end

  def test_gen_op_resolves_tmp_from_tmphash
    setup_devgen(self_name: :r)
    DevGen.instance_variable_set(:@tmphash, { _tmp0: 'protea::_add(x, 1)' })
    assert_equal 'protea::_add(x, 1)', DevGen.gen_op({ name: :_tmp0, type: :b32 })
  end
end
