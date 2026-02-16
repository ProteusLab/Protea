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

  def self.init_scope(scopes)
    scope = Protea::Scope.new(nil)

    scopes.reduce(@gscope, :merge).each do |name, val|
      if val.is_a?(Protea::Var)
        scope.insert_var(name, val)
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
      block[:body] << scope.to_h
    end
  end

  class RegBuilder < Protea::Plod::BuilderUtils
    attr_accessor :info, :inter

    def initialize(name, props, dscope)
      super()
      @info = { name: name, fields: [], methods: {} }
      @info.merge!(props)
      @dscope = dscope
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
      @info[:enableIf] = []
      System.semablocks << { scopes: [@dscope, @rscope], body: @info[:enableIf], block: block }
    end

    def field(name, lsb, size = 1)
      @info[:fields] << { name: name, lsb: lsb, size: size }

      f_type = Protea::Type::Bitvector.new(size)

      @rscope[name] = Protea::Var.new(name, f_type.name, nil, f_type)

      @inter.send(:define_method, name) do
        btype = Protea::Type::Bitvector.new(size)
        scope.get_field_by_name(btype, self, name)
      end
    end

    def Method(name, **args, &block)
      ret_type = args.delete(:ret)
      ret_type = ret_type.name unless ret_type.nil?

      @info[:methods][name] = { args: args, ret: ret_type, body: [] }

      lscope = {}
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

    def initialize
      super()
      @info = { registers: [], methods: {}, fields: {}, enums: {}, consts: {} }
      @dscope = {}
    end

    def Register(name, **props, &block)
      reg_builder = RegBuilder.new(name, props, @dscope)
      reg_builder.instance_eval(&block)
      @info[:registers] << reg_builder.info

      reg_type = Protea::Type.TypeObject("#{@info[:name]}::#{name}", reg_builder.inter).new

      @dscope[name] = Protea::Var.new(name, reg_type.name, nil, reg_type)
      nil
    end

    def Field(name, type)
      raise "Invalid type: #{type}" unless type.is_a?(Protea::Type::TypeObject)

      @dscope[name] = Protea::Var.new(name, type.name, nil, type)
      @info[:fields][name] = type.to_s
    end

    def Enum(name, &block)
      enum_bldr = EnumBuilder.new
      enum_bldr.instance_eval(&block)
      @info[:enums][name] = enum_bldr.values

      inter = Module.new

      enum_bldr.values.each do |key, _|
        inter.send(:define_method, key) do
          scope.stmt(:get_enum_value, [name, key])
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

      @info[:methods][name] = { args: args, ret: ret_type_name, body: [] }

      @dscope[name] = ret_type

      lscope = {}
      args.each do |name, type|
        lscope[name] = Protea::Var.new(name, type.name, nil, type)
        args[name] = type.to_s
      end

      System.semablocks << { scopes: [@dscope, lscope], body: @info[:methods][name][:body], block: block }
    end
  end

  def self.Device(name, &block)
    device_builder = DeviceBuilder.new
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

      @info[:methods][name] = { args: args, ret: ret_type_name, body: [] }

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
    struct_builder = StructBuilder
    struct_builder.instance_eval(&block)
    @desc[:structures][name] = struct_builder.info

    struct_type = Protea::Type.TypeObject(name, struct_builder.inter).new

    puts "add " + name.to_s

    singleton_class.send(:define_method, name) do
      struct_type
    end
  end

  def self.AbstractStruct(name)
    abstrStructInter = Module.new do
      def method_missing(name, *args)
        scope.stmt(name, [self] + args)
      end
    end

    struct_type = Protea::Type.TypeObject(name, abstrStructInter).new

    singleton_class.send(:define_method, name) do
      struct_type
    end

    @desc[:structures][name] = { kind: :abstract }
  end

  def self.AbstractObject(name, type)
    raise "Invalid type: #{type}" unless type.is_a?(Protea::Type::TypeObject)

    @gscope[name] = Protea::Var.new(name, type.name, nil, type)
    @desc[:objects][name] = type.to_s
  end

  def self.AbstractMethod(name, **args)
    @gscope[name] = args[:ret]
  end
end
