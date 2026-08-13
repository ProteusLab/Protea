# frozen_string_literal: true

require_relative '../helper'

class PlodFrontendTests < Protea::PlodTestCase
  def test_register_fields
    System::Device(:D) do
      Register(:r, size: 0x4, offset: 0x0) do
        field :a, 0x0
        field :b, 0x4, 0x2
      end
    end

    reg = System.desc[:devices][:D][:registers][:r]
    assert_equal 0x4, reg[:size]
    assert_equal 0x0, reg[:offset]
    assert_equal({ a: { lsb: 0, size: 1 }, b: { lsb: 4, size: 2 } }, reg[:fields])
    assert_equal({}, reg[:methods])
  end

  def test_register_field_array_range
    System::Device(:D) do
      Register(:r, size: 0x1, offset: 0x0) do
        field :a, [4, 7]
      end
    end

    assert_equal({ lsb: 4, size: 4 }, System.desc[:devices][:D][:registers][:r][:fields][:a])
  end

  def test_register_seqn_prop
    System::Device(:D) do
      Register(:r, size: 0x4, offset: 0x0, seqn: 0x1000) {}
    end

    assert_equal 0x1000, System.desc[:devices][:D][:registers][:r][:seqn]
  end

  def test_device_field
    System::Device(:D) do
      Field(:f, Int())
    end

    assert_equal({ type: :int, init_args: [] }, System.desc[:devices][:D][:fields][:f])
  end

  def test_abstract_field
    System::Device(:D) do
      AbstractField(:af, Int())
    end

    assert_equal :int, System.desc[:devices][:D][:abstr_fields][:af]
  end

  def test_const
    System::Device(:D) do
      Const(:c, Int(), 42)
    end

    assert_equal({ type: :int, val: 42 }, System.desc[:devices][:D][:consts][:c])
  end

  def test_enum
    System::Device(:D) do
      Enum(:e) do
        a 1
        b 2
      end
    end

    assert_equal({ 'a' => 1, 'b' => 2 }, System.desc[:devices][:D][:enums][:e])
  end

  def test_struct_fields
    System::Struct(:S) do
      Field(:f, Int())
    end

    struct = System.desc[:structures][:S]
    assert_equal :int, struct[:fields][:f]
    assert_equal({}, struct[:methods])
  end

  def test_method_return_lowers_to_ret
    System::Device(:D) do
      Method(:foo, x: Int()) do
        Return x
      end
    end
    System.process_semablocks

    tree = System.desc[:devices][:D][:methods][:foo][:body][:tree]
    assert_equal 1, tree.length
    assert_equal :ret, tree[0][:name]
    assert_equal :x, tree[0][:oprnds][0][:name]
    assert_equal :int, tree[0][:oprnds][0][:type]
  end

  def test_let_binop_produces_add_then_let
    System::Device(:D) do
      Method(:foo, x: Int()) do
        Let :y, Int(), x + 1
      end
    end
    System.process_semablocks

    tree = System.desc[:devices][:D][:methods][:foo][:body][:tree]
    add_stmt = tree.find { |s| s[:name] == :add }
    refute_nil add_stmt

    let_stmt = tree.find { |s| s[:name] == :let }
    refute_nil let_stmt
    assert_equal :y, let_stmt[:oprnds][0][:name]
    assert_equal add_stmt[:oprnds][0][:name], let_stmt[:oprnds][1][:name]
  end

  def test_if_else_scopes
    System::Device(:D) do
      Method(:foo, x: Int()) do
        If(x == 0) do
          x[] = 1
        end
        Else do
          x[] = 2
        end
      end
    end
    System.process_semablocks

    tree = System.desc[:devices][:D][:methods][:foo][:body][:tree]
    refute_nil(tree.find { |s| s[:name] == :eq })

    if_stmt = tree.find { |s| s[:name] == :if }
    refute_nil if_stmt
    assert if_stmt[:oprnds][1].key?(:tree)
    assert_equal :let, if_stmt[:oprnds][1][:tree][0][:name]

    else_stmt = tree.find { |s| s[:name] == :else }
    refute_nil else_stmt
    assert else_stmt[:oprnds][0].key?(:tree)
    assert_equal :let, else_stmt[:oprnds][0][:tree][0][:name]
  end

  def test_constructor_init_and_body
    System::Device(:D) do
      Constructor(params: Int()) do
        Init(:a, params)
        Body do
          params[] = 1
        end
      end
    end
    System.process_semablocks

    tree = System.desc[:devices][:D][:ctor][:body][:tree]
    init = tree.find { |s| s[:name] == :voidcall && s[:oprnds][0] == :Init }
    refute_nil init
    assert_equal :a, init[:oprnds][1]
    assert_equal :params, init[:oprnds][2][:name]

    body = tree.find { |s| s[:name] == :body }
    refute_nil body
  end
end
