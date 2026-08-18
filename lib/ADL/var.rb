require_relative 'base'
require 'Utility/type'

module SimInfra
  class Var
    include SimInfra
    attr_reader :scope, :name, :type, :regset

    def initialize(scope, name, type, regset = nil)
      @scope = scope
      @name = name
      @type = type
      @regset = regset
    end

    # Syntax "var[]=value" is used to assign variable
    # it's similar to "var[hi:lo]=value" for partial assignment
    def []=(other)
      @scope.stmt(:let, [self, other]) if regset.nil?
      @scope.stmt(:writeReg, [self, other]) unless regset.nil?
    end

    # dumps states and disables @scope dump
    def inspect = "#{@name}:#{@type} (#{@scope.object_id})"

    def to_h
      {
        name: @name,
        type: @type,
        regset: @regset
      }
    end

    def self.from_h(h, scope)
      Var.new(scope, h[:name], h[:type], h[:regset])
    end
  end
end

module SimInfra
  #
  class Var
    def +(other) = @scope.add(self, other)
    def -(other) = @scope.sub(self, other)
    def <<(other) = @scope.shl(self, other)
    def <(other) = @scope.lt(self, other)
    def <=(other) = @scope.le(self, other)
    def >(other) = @scope.gt(self, other)
    def >=(other) = @scope.ge(self, other)
    def ^(other) = @scope.xor(self, other)
    def >>(other) = @scope.shr(self, other)
    def |(other) = @scope.or(self, other)
    def &(other) = @scope.and(self, other)
    def ==(other) = @scope.eq(self, other)
    def !=(other) = @scope.ne(self, other)
    def [](r, l) = @scope.extract(self, r, l)

    def f = @scope.cast(self, ('f' + Utility.get_type(@type).bitsize.to_s).to_sym)
    def u = @scope.cast(self, ('u' + Utility.get_type(@type).bitsize.to_s).to_sym)
    def s = @scope.cast(self, ('s' + Utility.get_type(@type).bitsize.to_s).to_sym)
    def b = @scope.cast(self, ('b' + Utility.get_type(@type).bitsize.to_s).to_sym)
    def r(regset) = @scope.get_reg(self, regset, ('r' + Utility.get_type(@type).bitsize.to_s).to_sym)

    def method_missing(name, *regset)
      if regset.empty?
        instance_eval "def #{name}(); @scope.cast(self, (#{name}).to_sym); end", __FILE__, __LINE__
        @scope.cast(self, name.to_sym)
      else
        instance_eval "def #{name}(regset);  @scope.get_reg(self, regset, (#{name}).to_sym); end", __FILE__,
                      __LINE__ - 1
        @scope.get_reg(self, *regset, name.to_sym)
      end
    end

    def set_regset(regset)
      @regset = regset
    end
  end

  class Memory
    attr_accessor :scope

    def initialize(scope)
      @scope = scope
    end

    def [](addr, type) = @scope.readMem(addr, type)

    def[]=(addr, expr)
      @scope.writeMem(addr, expr)
    end
  end
end
