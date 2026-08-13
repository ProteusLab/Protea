require 'Common/scope'
require 'Common/type'

module Protea
  module Plod
    # Dumy
    class BuilderUtils
      include Type::Utils
    end
  end
end

module System
  @desc = {
    devices: {},
    structures: {},
    objects: {}
  }

  @semablocks = []
  @gscope = {}

  def self.desc
    @desc
  end

  def self.semablocks
    @semablocks
  end

  def self.reset
    @desc = { devices: {}, structures: {}, objects: {} }
    @semablocks = []
    @gscope = {}
  end

  def self.init_scope(scopes)
    scope = Protea::Scope.new(nil)

    scopes.reduce(@gscope, :merge).each do |name, val|
      if val.is_a?(Protea::Var)
        scope.insert_var(name, val)
      elsif val.is_a?(Array)
        scope.add_method(name, val[0], val[1])
      else
        scope.add_method(name, val)
      end
    end

    scope
  end

  def self.process_semablocks
    @semablocks.each do |block|
      scope = init_scope(block[:scopes])
      Protea::Var.open_scope(scope)
      scope.instance_eval(&block[:block])
      Protea::Var.close_scope
      block[:body].replace(scope.to_h)
    end
  end

  class RegBuilder < Protea::Plod::BuilderUtils
    attr_accessor :info, :inter

    def initialize(props, dscope, regname)
      super()
      @info = { fields: {}, methods: {} }
      @info.merge!(props)
      @dscope = dscope
      @regname = regname
      @rscope = {}
      @inter = Module.new
    end

    def size(value)
      @info[:size] = value
    end

    def offset(value)
      @info[:offset] = value
    end

    def type(value)
      @info[:type] = value
    end

    def enableIf(&block)
      @info[:enableIf] = {}
      System.semablocks << { scopes: [@dscope, @rscope], body: @info[:enableIf], block: block }
    end

    def field(name, lsb, size = 1)
      if (lsb.is_a?(Array))
        size = lsb[1] - lsb[0] + 1
        lsb = lsb[0]
      end

      @info[:fields][name] = { lsb: lsb, size: size }

      f_type = Protea::Type::Regfield.new(size)

      @rscope[name] = Protea::Var.new(name, f_type.name, nil, f_type)

      @inter.send(:define_method, name) do
        btype = Protea::Type::Regfield.new(size)
        scope.get_reg_field_by_name(btype, self, name)
      end
    end

    def Method(name, **args, &block)
      ret_type = args.delete(:ret)
      ret_type = ret_type.name unless ret_type.nil?

      @info[:methods][name] = { args: args, ret: ret_type, body: {} }

      @inter.send(:define_method, name) do |*args|
        scope.membercall(ret_type, self, name, *args)
      end

      @rscope[name] = [ret_type, "#{@regname}_#{name}".to_sym]

      lscope = { seqid: Protea::Var.new(:seqid, Int().name, nil, Int()) }
      args.each do |name, type|
        lscope[name] = Protea::Var.new(name, type.name, nil, type)
        args[name] = type.to_s
      end

      System.semablocks << { scopes: [@dscope, @rscope, lscope], body: @info[:methods][name][:body], block: block }
      nil
    end
  end

  class EnumBuilder 
    attr_accessor :values

    def initialize
      @values = {}
    end

    def method_missing(name, *args)
      @values[name.to_s] = args[0]
    end
  end

  class DeviceBuilder < Protea::Plod::BuilderUtils
    attr_accessor :info

    def initialize(name)
      super()
      @name = name
      @info = { registers: {}, methods: {}, fields: {}, abstr_fields: {}, enums: {}, consts: {}, lambdas: {} }
      @dscope = {}
    end

    def Register(name, **props, &block)
      reg_builder = RegBuilder.new(props, @dscope, name)
      reg_builder.instance_eval(&block)
      @info[:registers][name] = reg_builder.info

      reg_type = Protea::Type.TypeObject("#{@name}::#{name}".to_sym, reg_builder.inter).new

      reg_seq_inter = Module.new do
        define_method(:at) do |idx|
          scope.get_container_element(Protea::Type::Bitvector.new(reg_builder.info[:size] * 8), self, idx)
        end

        define_method(:set) do |idx, val|
          scope.set_container_element(self, idx, val)
        end

        include reg_builder.inter
      end

      reg_seq_type = Protea::Type.TypeObject("#{@name}::#{name}_seq".to_sym, reg_seq_inter).new
      @info[:registers][name][:type] = reg_seq_type.to_s

      System.singleton_class.send(:define_method, "#{name}T") do
        reg_type
      end

      @dscope[name] = Protea::Var.new(name, reg_seq_type.name, nil, reg_seq_type)
      nil
    end

    def Field(name, type, *init_args)
      raise "Invalid type: #{type}" unless type.is_a?(Protea::Type::TypeObject)

      @dscope[name] = Protea::Var.new(name, type.name, nil, type)
      @info[:fields][name] = { type: type.to_s, init_args: init_args }
    end

    def AbstractField(name, type)
      raise "Invalid type: #{type}" unless type.is_a?(Protea::Type::TypeObject)

      @dscope[name] = Protea::Var.new(name, type.name, nil, type)
      @info[:abstr_fields][name] = type.to_s
    end

    def Enum(name, &block)
      enum_bldr = EnumBuilder.new
      enum_bldr.instance_eval(&block)
      @info[:enums][name] = enum_bldr.values

      inter = Module.new

      enum_bldr.values.each do |key, _|
        inter.send(:define_method, key) do
          scope.get_enum_val(name, key)
        end
      end

      enum_type = Protea::Type.TypeObject(name, inter).new
      @dscope[name] = Protea::Var.new(name, enum_type.name, nil, enum_type)
    end

    def Const(name, type, value)
      @info[:consts][name] = { type: type.name, val: value }
      @dscope[name] = Protea::Var.new(name, type.name, nil, type)
    end

    def AbstractMethod(name, **args)
      @dscope[name] = args[:ret]
    end

    def Method(name, **args, &block)
      ret_type = args.delete(:ret)
      ret_type_name = ret_type
      ret_type_name = ret_type.name unless ret_type.nil?

      @info[:methods][name] = { args: args, ret: ret_type_name, body: {} }

      @dscope[name] = ret_type

      lscope = {}
      args.each do |name, type|
        lscope[name] = Protea::Var.new(name, type.name, nil, type)
        args[name] = type.to_s
      end

      System.semablocks << { scopes: [@dscope, lscope], body: @info[:methods][name][:body], block: block }
    end

    def Lambda(**args, &block)
      lambda_name = "lambda_#{@info[:lambdas].size}".to_sym
      lambda_type = Protea::Type::Lambda.new

      @info[:lambdas][lambda_name] = { args: args, body: {} }

      lscope = {}
      args.each do |name, type|
        lscope[name] = Protea::Var.new(name, type.name, nil, type)
        args[name] = type.to_s
      end

      System.semablocks << { scopes: [@dscope, lscope], body: @info[:lambdas][lambda_name][:body], block: block }

      @dscope[lambda_name] = Protea::Var.new(lambda_name, lambda_type.name, nil, lambda_type)
      @dscope[lambda_name].to_h
    end

    def Constructor(**args, &block)
      @info[:ctor] = { args: args, init: {}, body: {} }

      lscope = {}
      args.each do |name, type|
        lscope[name] = Protea::Var.new(name, type.name, nil, type)
        args[name] = type.to_s
      end

      lscope[:Init] = nil

      System.semablocks << { scopes: [@dscope, lscope], body: @info[:ctor][:body], block: block }
    end
  end

  def self.Device(name, &block)
    device_builder = DeviceBuilder.new(name)
    device_builder.instance_eval(&block)
    @desc[:devices][name] = device_builder.info
    nil
  end

  class StructBuilder < Protea::Plod::BuilderUtils
    attr_accessor :info, :inter

    def initialize
      super()
      @info = { methods: {}, fields: {} }
      @dscope = {}
      @inter = Module.new
    end

    def Method(name, **args, &block)
      ret_type = args.delete(:ret)
      ret_type_name = ret_type
      ret_type_name = ret_type.name unless ret_type.nil?

      @info[:methods][name] = { args: args, ret: ret_type_name, body: {} }

      @dscope[name] = ret_type

      lscope = {}
      args.each do |name, type|
        lscope[name] = Protea::Var.new(name, type.name, nil, type)
        args[name] = type.to_s
      end

      System.semablocks << { scopes: [@dscope, lscope], body: @info[:methods][name][:body], block: block }

      @inter.send(:define_method, name) do |*args|
        if ret_type.nil?
          scope.stmt(:call, [self, name, *args])
        else
          scope.call(ret_type, self, name, *args)
        end
      end
    end

    def Field(name, type)
      raise "Invalid type: #{type}" unless type.is_a?(Protea::Type::TypeObject)

      @dscope[name] = Protea::Var.new(name, type.name, nil, type)
      @info[:fields][name] = type.to_s
    end
  end

  def self.Struct(name, &block)
    struct_builder = StructBuilder.new
    struct_builder.instance_eval(&block)
    @desc[:structures][name] = struct_builder.info

    struct_type = Protea::Type.TypeObject(name, struct_builder.inter).new

    puts "add " + name.to_s

    singleton_class.send(:define_method, name) do
      struct_type
    end
  end

  class AbstrStructBuilder < Protea::Plod::BuilderUtils
    attr_accessor :info, :inter

    def initialize
      super()
      @info = { kind: :abstract, methods: {}, fields: {} }
      @inter = Module.new
    end

    def Method(name, **args)
      ret_type = args.delete(:ret)
      ret_type_name = ret_type
      ret_type_name = ret_type.name unless ret_type.nil?

      args.each do |name, type|
        args[name] = type.to_s
      end

      @info[:methods][name] = { args: args, ret: ret_type_name, body: {} }

      @inter.send(:define_method, name) do |*cargs|
        if ret_type.nil?
          scope.voidmembercall(self, name, *cargs)
        else
          scope.membercall(ret_type, self, name, *cargs)
        end
      end
    end

    def Field(name, type)
      raise "Invalid type: #{type}" unless type.is_a?(Protea::Type::TypeObject)

      @info[:fields][name] = { type: type.to_s }

      @inter.send(:define_method, name) do 
        scope.get_field_by_name(type, self, name)
      end
    end
  end

  def self.AbstractStruct(name, &block)
    as_builder = AbstrStructBuilder.new
    as_builder.instance_eval(&block)
    @desc[:structures][name] = as_builder.info

    as_builder.inter.send(:define_method, :method_missing) do |name, *args|
      scope.voidmembercall(self, name, *args)
    end

    as_type = Protea::Type.TypeObject(name, as_builder.inter).new

    singleton_class.send(:define_method, name) do
      as_type
    end
  end

  def self.AbstractObject(name, type)
    raise "Invalid type: #{type}" unless type.is_a?(Protea::Type::TypeObject)

    @gscope[name] = Protea::Var.new(name, type.name, nil, type)
    @desc[:objects][name] = type.to_s
  end

  def self.AbstractMethod(name, **args)
    @gscope[name] = args[:ret]
  end

  def self.Self()
    self_type = Protea::Type::Bitvector.new(8)
    Protea::Var.new(:self, self_type.name, nil, self_type)
  end
end
