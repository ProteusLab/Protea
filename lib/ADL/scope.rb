require_relative 'base'
require_relative 'var'
require 'Utility/type'

module SimInfra
  def assert(condition, msg = nil)
    raise msg unless condition
  end

  class Scope
    include GlobalCounter # used for temp variables IDs
    include SimInfra

    attr_reader :tree, :vars, :parent, :mem

    def initialize(parent)
      @tree = []
      @vars = {}
      @mem = Memory.new(self)
      @parent = parent
    end
    # resolve allows to convert Ruby Integer constants to Constant instance

    def var(name, type, attrs = nil)
      method(name, type)
      stmt :new_var, [@vars[name]], attrs # returns @vars[name]
    end

    def method(name, type, regset = nil)
      @vars[name] = SimInfra::Var.new(self, name, type, regset) # return var
      instance_eval "def #{name}(); return @vars[:#{name}]; end", __FILE__, __LINE__
    end

    def rmethod(name, regset, type)
      @vars[name] = SimInfra::Var.new(self, name, type, regset) # return var
      instance_eval "def #{name}(); return @vars[:#{name}]; end", __FILE__, __LINE__
    end

    def add_var(name, type, attrs = nil)
      var(name, type, attrs)
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

      Constant.new(self, "const_#{next_counter}", what) if what.class == Integer
    end

    def binOp(a, b, op)
      binOpWType(a, b, op,
                 Utility.get_type(a.type).typeof == :r ? ('b' + Utility.get_type(a.type).bitsize.to_s).to_sym : a.type)
    end

    def binOpWType(a, b, op, t)
      a = resolve_const(a)
      b = resolve_const(b)
      # TODO: check constant size <= bitsize(var)
      # assert(a.type== b.type|| a.type == :iconst || b.type== :iconst)
      stmt op, [tmpvar(t), a, b]
    end

    # redefine! add & sub will never be the same
    def add(a, b) = binOp(a, b, :add)
    def sub(a, b) = binOp(a, b, :sub)
    def mul(a, b) = binOp(a, b, :mul)
    def div(a, b) = binOp(a, b, :div)
    def rem(a, b) = binOp(a, b, :rem)
    def shl(a, b) = binOp(a, b, :shl)
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
      add_var(sym, type)
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

    private def tmpvar(type) = var("_tmp#{next_counter}".to_sym, type)
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
