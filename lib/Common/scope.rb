require_relative 'base'
require_relative 'var'
require 'Utility/type'
require_relative 'type'

module Protea
    class IrStmt
        attr_reader :name, :oprnds, :attrs
        def initialize(name, oprnds, attrs)
            @name = name; @oprnds = oprnds; @attrs = attrs;
        end

        def to_h
            {
                name: @name,
                oprnds: @oprnds.map { |o|
                    if o.class == Var || o.class == Constant || o.class == Scope
                        o.to_h
                    else
                        o
                    end
                },
                attrs: @attrs,
            }
        end

        def self.from_h(h)
            IrStmt.new(h[:name], h[:oprnds], h[:attrs])
        end
    end
end

module Protea
  def assert(condition, msg = nil)
    raise msg unless condition
  end

  class Scope
    include GlobalCounter # used for temp variables IDs
    include Protea
    include Type::Utils

    attr_reader :vars, :mem
    attr_accessor :tree, :parent

    def initialize(parent)
      @tree = []
      @vars = {}
      @mem = Memory.new(self)
      @parent = parent
    end
    # resolve allows to convert Ruby Integer constants to Constant instance

    def var(name, type, attrs = nil, plod_type = Type::Empty.new())
      if type.is_a?(Type::TypeObject)
        plod_type = type
        type = plod_type.name
      end

      method(name, type, nil, plod_type)
      stmt :new_var, [@vars[name]], attrs # returns @vars[name]
    end

    def method(name, type, regset = nil, plod_type = Type::Empty.new())
      @vars[name] = Protea::Var.new(name, type, regset, plod_type) # return var
      instance_eval "def #{name}(); return @vars[:#{name}]; end", __FILE__, __LINE__
      @vars[name]
    end

    def rmethod(name, regset, type)
      @vars[name] = Protea::Var.new(name, type, regset) # return var
      instance_eval "def #{name}(); return @vars[:#{name}]; end", __FILE__, __LINE__
    end

    def add_var(name, type, attrs = nil, plod_type = Type::Empty.new())
      var(name, type, attrs, plod_type)
      self
    end

    def add_rvar(name, regset, type)
      rmethod(name, regset, type)
      stmt :new_var, [@vars[name]]
      self
    end

    def add_arvar(name, regset, type, attrs = nil)
      rmethod(name, regset, type)
      stmt :new_var, [@vars[name]], attrs
      self
    end

    def resolve_const(what)
      return what if (what.class == Var) or (what.class == Constant) # or other known classes

      Constant.new(self, "const_#{next_counter}", what) if what.class == Integer || what.class == String
    end

    def binOp(a, b, op)
      if a.plod_type.nil? || a.plod_type.is_a?(Type::Empty)
        binOpWType(a, b, op,
                 Utility.get_type(a.type).typeof == :r ? ('b' + Utility.get_type(a.type).bitsize.to_s).to_sym : a.type)
      else
        binOpWType(a, b, op, a.plod_type.name, a.plod_type)
      end
    end

    def binOpWType(a, b, op, t, plod_type = Type::Empty.new())
      a = resolve_const(a)
      b = resolve_const(b)
      # TODO: check constant size <= bitsize(var)
      # assert(a.type== b.type|| a.type == :iconst || b.type== :iconst)
      stmt op, [tmpvar(t, plod_type), a, b]
    end

    # redefine! add & sub will never be the same
    def add(a, b) = binOp(a, b, :add)
    def sub(a, b) = binOp(a, b, :sub)
    def mul(a, b) = binOp(a, b, :mul)
    def div(a, b) = binOp(a, b, :div)
    def shl(a, b) = binOp(a, b, :shl)
    def rem(a, b) = binOp(a, b, :rem)
    def lt(a, b) = binOpWType(a, b, :lt, :b1)
    def gt(a, b) = binOpWType(a, b, :gt, :b1)
    def le(a, b) = binOpWType(a, b, :le, :b1)
    def ge(a, b) = binOpWType(a, b, :ge, :b1)
    def xor(a, b) = binOp(a, b, :xor)
    def shr(a, b) = binOp(a, b, :shr)
    def ashr(a, b) = binOp(a, b, :ashr)
    def or(a, b) = binOp(a, b, :or)
    def and(a, b) = binOp(a, b, :and)
    def eq(a, b) = binOpWType(a, b, :eq, :b1)
    def ne(a, b) = binOpWType(a, b, :ne, :b1)

    def select(p, a, b)
      a = resolve_const(a)
      b = resolve_const(b)
      stmt :select, [tmpvar(a.type), p, a, b]
    end

    def extract(x, r, l)
      stmt :extract, [tmpvar(('b' + (r - l + 1).to_s).to_sym), x, resolve_const(r), resolve_const(l)]
    end

    def neg(expr) = stmt(:neg, [tmpvar(expr.type), expr])
    def not(expr) = stmt(:not, [tmpvar(expr.type), expr])

    def zext(a, type) = stmt(:zext, [tmpvar(type), a])

    def get_reg(expr, regset, type) = rlet("_reg_#{next_counter}".to_sym, regset, type, expr)

    def write(rfile, reg, expr) = stmt(:write, [rfile, reg, expr])
    def writeMem(addr, expr) = stmt(:writeMem, [addr, expr])
    def readMem(addr, type) = stmt(:readMem, [tmpvar(type), addr])

    def read(rfile, reg)
      v = tmpvar(:b32)
      stmt :read, [v, rfile, reg]
    end

    def cast(expr, type) = stmt(:cast, [tmpvar(type), expr])

    def let(*args)
      case args.length
      when 3
        jlet(args[0], args[1], args[2])
      when 4
        if args[1].is_a? Symbol
          rlet(args[0], args[1], args[2], args[3])
        else
          alet(args[0], args[1], args[2], args[3])
        end
      when 5
        arlet(args[0], args[1], args[2], args[3], args[4])
      else
        raise "Invalid number of arguments for let: #{args.length}"
      end
    end

    def jlet(sym, type, expr)
      plod_type = Type::Empty.new
      if type.is_a?(Type::TypeObject)
        plod_type = type
        type = plod_type.name
      end

      add_var(sym, type, nil, plod_type)
      stmt(:let, [@vars[sym], expr])
    end

    def alet(sym, attrs, type, expr)
      add_var(sym, type, attrs)
      stmt(:let, [@vars[sym], expr])
    end

    def rlet(sym, regset, type, expr)
      add_rvar(sym, regset, type)
      stmt(:let, [@vars[sym], expr])
    end

    def arlet(sym, regset, attrs, type, expr)
      add_arvar(sym, regset, type, attrs)
      stmt(:let, [@vars[sym], expr])
    end

    def branch(expr) = stmt(:branch, [expr])

    private def tmpvar(type, plod_type = Type::Empty.new()) = var("_tmp#{next_counter}".to_sym, type, nil, plod_type)
    # stmtadds statement into tree and retursoperand[0]
    # which result in near all cases
    def stmt(name, operands, attrs = nil)
      for i in 1...operands.length
        operands[i] = read_transform(name, operands[i])
      end
      @tree << IrStmt.new(name, operands, attrs)
      operands[0]
    end

    def read_transform(operation_name, op)
      if op.class == Var && !op.regset.nil?
        x = tmpvar(('b' + op.type.to_s[1..-1]).to_sym)
        @tree << IrStmt.new(:readReg, [x, op], nil)
        x
      else
        op
      end
    end

    # PLOD specific part

    def get_reg_field_by_name(plod_type, expr, name) = stmt(:get_reg_field, [tmpvar(plod_type.name, plod_type), expr, name])

    def get_field_by_name(plod_type, expr, name)
      type = Type::Ref.new(plod_type)
      stmt(:get_field, [tmpvar(type.name, type), expr, name])
    end

    def get_container_element(plod_type, container, idx) = stmt(:get_cntr_elem, [tmpvar(plod_type.name, plod_type), container, idx])

    def set_container_element(container, idx, val) = stmt(:set_cntr_elem, [container, idx, val])

    def insert_var(name, var)
      @vars[name] = var
      instance_eval "def #{name}(); return @vars[:#{name}]; end", __FILE__, __LINE__
      var
    end

    def call(type, expr, name, *args) = stmt(:call, [tmpvar(type.name, type), expr, name, *args])

    def voidmembercall(obj, name, *args) = stmt(:voidmembercall, [obj, name, *args])

    def membercall(type, obj, name, *args)
      if type.nil?
        stmt(:voidmembercall, [obj, name, *args])
      else
        stmt(:membercall, [tmpvar(type.name, type), obj, name, *args])
      end
    end

    def get_enum_val(enum, key)
      enum_type = Protea::Type::Int.new
      stmt(:get_enum_value, [tmpvar(enum_type.name, enum_type), enum, key])
    end

    def add_method(name, ret_type, call_name = name)
      if ret_type.nil?
        define_singleton_method(name) do |*args|
          stmt(:voidcall, [call_name, *args])
        end
      else
        define_singleton_method(name) do |*args|
          stmt(:call, [tmpvar(ret_type.name, ret_type), call_name, *args])
        end
      end
    end

    def Return(*expr) = stmt(:ret, [*expr])

    def Cast(type, var)
      stmt(:cast, [tmpvar(type.name, type), var])
    end

    def Let(*args) = let(*args)

    def Var(name, type, attrs = nil, plod_type = Type::Empty.new()) = var(name, type, attrs, plod_type)

    def create_subscope
      subscope = clone
      subscope.tree = []
      subscope.parent = self
      subscope
    end

    def If(cond, &block)
      subscope = create_subscope
      stmt(:if, [cond, subscope])
      Var.open_scope(subscope)
      subscope.instance_eval(&block)
      Var.close_scope
    end

    def Elseif(cond, &block)
      subscope = create_subscope
      stmt(:elseif, [cond, subscope])
      Var.open_scope(subscope)
      subscope.instance_eval(&block)
      Var.close_scope
    end

    def Else(&block)
      subscope = create_subscope
      stmt(:else, [subscope])
      Var.open_scope(subscope)
      subscope.instance_eval(&block)
      Var.close_scope
    end

    def For(**args, &block)
      subscope = create_subscope
      stmt(:for, [args[:iter], args[:init], args[:end], subscope])
      Var.open_scope(subscope)
      subscope.instance_eval(&block)
      Var.close_scope
    end

    def Body(&block)
      subscope = create_subscope
      stmt(:body, [subscope])
      Var.open_scope(subscope)
      subscope.instance_eval(&block)
      Var.close_scope
    end

    def GetPtr(var)
      ret_type = Type::Ptr.new(var.plod_type)
      stmt(:get_ptr, [tmpvar(ret_type.name, ret_type), var])
    end

    def to_h
      {
        tree: @tree.map(&:to_h)
      }
    end

    def self.from_h(h)
      scope = Scope.new(nil)
      scope.instance_variable_set(:@tree, h[:tree].map { |s| IrStmt.from_h(s) })
      scope
    end

    def pretty_print(q)
      q.object_address_group(self) do
        variables_to_show = instance_variables - %i[@vars @mem]

        q.seplist(variables_to_show, -> { q.text ',' }) do |v|
          q.breakable
          q.text v.to_s
          q.text '='
          q.group(1) do
            q.breakable ''
            q.pp instance_variable_get(v)
          end
        end
      end
    end
  end
end
