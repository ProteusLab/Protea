# lira/ir_std.rb
require_relative 'ir'
require_relative 'arch'

module StmtKind
  INPUT = "input"
  OUTPUT = "output"
  READ = "read"
  WRITE = "write"
  OP = "op"
  ENV = "env"
  COND_ENV = "cond_env"
  CONST = "const"
  DYN_CONST = "dyn_const"
end

class StmtInput
  attr_accessor :id_

  def self.kind; StmtKind::INPUT; end

  def initialize(id_)
    @id_ = id_
  end
end

class StmtOutput
  attr_accessor :id_, :value

  def self.kind; StmtKind::OUTPUT; end

  def initialize(id_, value)
    @id_ = id_
    @value = value
  end
end

class StmtRead
  attr_accessor :rf, :rsi

  def self.kind; StmtKind::READ; end

  def initialize(rf, rsi)
    @rf = rf
    @rsi = rsi
  end
end

class StmtWrite
  attr_accessor :rf, :rsi, :value

  def self.kind; StmtKind::WRITE; end

  def initialize(rf, rsi, value)
    @rf = rf
    @rsi = rsi
    @value = value
  end
end

class StmtOp
  attr_accessor :op, :args

  def self.kind; StmtKind::OP; end

  def initialize(op, args)
    @op = op
    @args = args
  end
end

class StmtEnv
  attr_accessor :env, :args

  def self.kind; StmtKind::ENV; end

  def initialize(env, args)
    @env = env
    @args = args
  end
end

class CondEnv
  attr_accessor :env, :cond, :on_false, :inputs

  def self.kind; StmtKind::COND_ENV; end

  def initialize(env, cond, on_false, inputs)
    @env = env
    @cond = cond
    @on_false = on_false
    @inputs = inputs
  end
end

class StmtIndex; end
class StmtConst
  attr_accessor :value

  def self.kind; StmtKind::CONST; end

  def initialize(value); @value = value; end
end
class StmtDynConst
  attr_accessor :name

  def self.kind; StmtKind::DYN_CONST; end

  def initialize(name); @name = name; end
end
class StmtGather
  attr_accessor :value, :index, :default
  def initialize(value, index, default); @value = value; @index = index; @default = default; end
end
class StmtFold
  attr_accessor :op, :args
  def initialize(op, args); @op = op; @args = args; end
end
class StmtScan
  attr_accessor :op, :args
  def initialize(op, args); @op = op; @args = args; end
end
class StmtAlias
  attr_accessor :semantic, :args
  def initialize(semantic, args); @semantic = semantic; @args = args; end
end
