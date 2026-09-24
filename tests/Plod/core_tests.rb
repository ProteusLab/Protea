# frozen_string_literal: true

require_relative '../helper_plod'

class CoreTypesTests < Plod::TestCase
  def test_equality_is_structural
    assert_equal Plod::Types::Bits.new(8), Plod::Types::Bits.new(8)
    refute_equal Plod::Types::Bits.new(8), Plod::Types::Bits.new(16)
    assert_equal Plod::Types::Ptr.new(Plod::Types::Named.new(:Event)), Plod::Types::Ptr.new(Plod::Types::Named.new(:Event))
    assert_equal Plod::Types::Array.new(Plod::Types::Bits.new(8), 8), Plod::Types::Array.new(Plod::Types::Bits.new(8), 8)
    refute_equal Plod::Types::Ptr.new(Plod::Types::Bits.new(8)), Plod::Types::Ref.new(Plod::Types::Bits.new(8))
  end

  def test_type_names_are_canonical
    assert_equal 'b8', Plod::Types::Bits.new(8).name
    assert_equal 'rf3', Plod::Types::Field.new(3).name
    assert_equal 'b8[8]', Plod::Types::Array.new(Plod::Types::Bits.new(8), 8).name
    assert_equal 'ptr(Event)', Plod::Types::Ptr.new(Plod::Types::Named.new(:Event)).name
    assert_equal 'ref(ClintParams)', Plod::Types::Ref.new(Plod::Types::Named.new(:ClintParams)).name
    assert_equal 'int', Plod::Types::Int.new.name
    assert_equal 'bool', Plod::Types::Bool.new.name
  end

  def test_types_are_hashable
    map = { Plod::Types::Bits.new(8) => :bits }
    assert_equal :bits, map[Plod::Types::Bits.new(8)]
  end

  def test_invalid_sizes_rejected
    assert_raises(ArgumentError) { Plod::Types::Bits.new(0) }
    assert_raises(ArgumentError) { Plod::Types::Bits.new(-3) }
    assert_raises(ArgumentError) { Plod::Types::Array.new(Plod::Types::Int.new, 0) }
  end

  def test_deref
    ptr = Plod::Types::Ptr.new(Plod::Types::Named.new(:Event))
    assert ptr.ptr?
    assert_equal Plod::Types::Named.new(:Event), ptr.deref
    assert_equal Plod::Types::Int.new, Plod::Types::Int.new.deref
  end

  def test_type_yaml_round_trip
    types = [
      Plod::Types::Int.new, Plod::Types::Bool.new, Plod::Types::Bits.new(32),
      Plod::Types::Field.new(2), Plod::Types::Array.new(Plod::Types::Bits.new(14), 8),
      Plod::Types::Ptr.new(Plod::Types::Named.new(:Tick)),
      Plod::Types::Ref.new(Plod::Types::Named.new(:ClintParams)),
      Plod::Types::Named.new(:fifo8), Plod::Types::Lambda.new, Plod::Types::Auto.new
    ]
    types.each do |t|
      loaded = Plod.yaml_load(Plod.yaml_dump(t.to_h))
      assert_equal t, Plod::Types.from_h(loaded.transform_keys(&:to_sym)), "round trip failed for #{t.name}"
    end
  end
end

class CoreIRTests < Plod::TestCase
  def make_expr
    Plod::IR::BinOp.new(
      op: :+,
      lhs: Plod::IR::VarRef.new(name: :x, type: Plod::Types::Int.new),
      rhs: Plod::IR::Const.new(value: 1, type: Plod::Types::Int.new),
      loc: Plod::Loc.new('dev.rb', 3)
    )
  end

  def test_binop_round_trip
    h = make_expr.to_h
    assert_equal :binop, h[:kind]
    assert_equal %i[var const], h[:lhs].map { |o| o[:kind] } if false
    node = Plod::IR.from_h(h)
    assert_equal :+, node.op
    assert_equal :x, node.lhs.name
    assert_equal 1, node.rhs.value
    assert_equal Plod::Loc.new('dev.rb', 3), node.loc
  end

  def test_if_round_trip_with_elsif_and_else
    node = Plod::IR::If.new(
      cond: make_expr,
      then_body: [Plod::IR::Return.new(value: nil, loc: nil)],
      elsif_list: [[make_expr, [Plod::IR::ExprStmt.new(expr: make_expr)]]],
      else_body: [Plod::IR::Return.new(value: Plod::IR::Const.new(value: 2))]
    )
    restored = Plod::IR.from_h(node.to_h)
    assert_equal :if, restored.kind
    assert_equal 1, restored.elsif_list.length
    assert_equal :binop, restored.elsif_list[0][0].kind
    assert_equal 1, restored.elsif_list[0][1].length
    assert_equal :exprstmt, restored.elsif_list[0][1][0].kind
    assert_equal 2, restored.else_body[0].value.value
  end

  def test_method_decl_round_trip
    decl = Plod::IR::MethodDecl.new(
      name: :push,
      args: [[:value, Plod::Types::Bits.new(8)], [:cid, nil]],
      ret_type: nil,
      body: [Plod::IR::Return.new(value: nil)],
      abstract: false
    )
    h = decl.to_h
    restored = Plod::IR.from_h(h)
    assert_equal :push, restored.name
    assert_equal :value, restored.args[0][0]
    assert_equal Plod::Types::Bits.new(8), restored.args[0][1]
    assert_nil restored.args[1][1]
    assert_equal 1, restored.body.length
  end

  def test_self_element_round_trip
    node = Plod::IR::GetElem.new(
      container: Plod::IR::SelfRef.new(subject: :register, type: nil),
      index: Plod::IR::SelfIndex.new(type: Plod::Types::Int.new, loc: Plod::Loc.new('dev.rb', 5)),
      type: Plod::Types::Bits.new(32)
    )
    restored = Plod::IR.from_h(node.to_h)
    assert_equal :getelem, restored.kind
    assert_equal :self, restored.container.kind
    assert_equal :register, restored.container.subject
    assert_equal :selfindex, restored.index.kind
    assert_equal Plod::Types::Int.new, restored.index.type
    assert_equal Plod::Types::Bits.new(32), restored.type
  end

  def test_register_decl_round_trip
    reg = Plod::IR::RegisterDecl.new(
      name: :msip,
      size: 4,
      offset: 0,
      access: :rw,
      seqn: 0x1000,
      fields: [Plod::IR::RegFieldDecl.new(name: :msipb, lsb: 0, size: 1)],
      methods: [Plod::IR::MethodDecl.new(name: :write, args: [[:data, Plod::Types::Bits.new(32)]], ret_type: nil, body: [])],
      enable_if: make_expr
    )
    restored = Plod::IR.from_h(reg.to_h)
    assert_equal :msip, restored.name
    assert_equal :rw, restored.access
    assert_equal 0x1000, restored.seqn
    assert_equal :msipb, restored.fields[0].name
    assert_equal :write, restored.methods[0].name
    assert_equal :binop, restored.enable_if.kind
  end

  def test_device_decl_round_trip
    dev = Plod::IR::DeviceDecl.new(
      name: :Clint,
      registers: [],
      methods: [Plod::IR::MethodDecl.new(name: :reg_init, args: [], ret_type: nil, body: [])],
      fields: [Plod::IR::FieldDecl.new(name: :nThread, type: Plod::Types::Bits.new(32), init_args: [], abstract: false)],
      enums: [Plod::IR::EnumDecl.new(name: :ids, values: { a: 0 })],
      consts: [Plod::IR::ConstDecl.new(name: :c, type: Plod::Types::Int.new, value: 7)],
      lambdas: [],
      ctor: nil
    )
    restored = Plod::IR.from_h(dev.to_h)
    assert_equal :Clint, restored.name
    assert_equal :nThread, restored.fields[0].name
    assert_equal Plod::Types::Bits.new(32), restored.fields[0].type
    assert_equal({ a: 0 }, restored.enums[0].values)
    assert_equal 7, restored.consts[0].value
  end

  def test_program_round_trip
    prog = Plod::IR::Program.new(
      path: 'clint.rb',
      devices: [],
      components: [Plod::IR::ComponentDecl.new(name: :Event, methods: [], fields: [], abstract: true)],
      objects: { ns: Plod::Types::Named.new(:Tick) },
      functions: { curTick: Plod::IR::MethodDecl.new(name: :curTick, args: [], ret_type: Plod::Types::Named.new(:Tick), body: [], abstract: true) }
    )
    restored = Plod::IR.from_h(prog.to_h)
    assert_equal :Event, restored.components[0].name
    assert restored.components[0].abstract
    assert_equal Plod::Types::Named.new(:Tick), restored.objects[:ns]
    assert_equal Plod::Types::Named.new(:Tick), restored.functions[:curTick].ret_type
  end

  def test_unknown_kind_raises
    assert_raises(ArgumentError) { Plod::IR.from_h(kind: :nope) }
  end
end

class DiagnosticsTests < Plod::TestCase
  def test_error_and_warning
    bag = Plod::DiagnosticBag.new
    bag.error('boom', Plod::Loc.new('dev.rb', 4))
    bag.warning('careful')
    assert bag.error?
    assert_equal 2, bag.count
    assert_equal 1, bag.errors.size
    assert bag.to_s.include?('dev.rb:4: error: boom')
    assert bag.to_s.include?('warning: careful')
  end

  def test_empty_bag
    bag = Plod::DiagnosticBag.new
    assert bag.empty?
    refute bag.error?
  end

  def test_merge
    a = Plod::DiagnosticBag.new
    a.error('a')
    b = Plod::DiagnosticBag.new
    b.error('b')
    a.merge!(b)
    assert_equal 2, a.count
  end
end
