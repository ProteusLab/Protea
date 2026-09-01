# frozen_string_literal: true

require_relative 'slate'
require_relative 'env'
require_relative 'ir'
require_relative 'types'

module Plod
  module DeclTypes
    def expect_type!(value, what)
      return value if value.is_a?(Types::Base)

      raise Plod::Error.new("#{what}: expected a type, got #{value.inspect}", Loc.capture)
    end

    def process_signature(args, what)
      ret_type = args.delete(:ret)
      expect_type!(ret_type, "return type of #{what}") unless ret_type.nil?
      processed = args.map do |name, type|
        expect_type!(type, "argument #{name} of #{what}")
        [name.to_sym, type]
      end
      [processed, ret_type]
    end

    def method_missing(name, *args)
      type = @frontend.lookup_type(name)
      return type if type && args.empty?

      raise Plod::Error.new("unknown name or type '#{name}'#{@frontend.known_names_hint}", Loc.capture)
    end

    def respond_to_missing?(name, _include_private = false)
      @frontend.type_declared?(name) || super
    end
  end

  class EnumDeclContext < Slate
    def initialize(decl)
      @decl = decl
    end

    def method_missing(name, value)
      unless value.is_a?(Integer)
        raise Plod::Error.new("enum value #{name} must be an integer, got #{value.inspect}",
                              Loc.capture)
      end

      @decl.values[name.to_sym] = value
      nil
    end

    def respond_to_missing?(_name, _include_private = false)
      true
    end
  end

  class RegisterDeclContext < Slate
    include Types::Sugar
    include Types::BitSugar
    include DeclTypes

    attr_reader :decl, :enable_if_proc, :method_procs

    def initialize(frontend, name, props)
      @frontend = frontend
      @decl = IR::RegisterDecl.new(
        name: name,
        size: props[:size],
        offset: props[:offset],
        access: self.class.normalize_access(props[:type] || :rw),
        seqn: props[:seqn],
        fields: [],
        methods: [],
        enable_if: nil,
        loc: Loc.capture
      )
      @enable_if_proc = nil
      @method_procs = {}.compare_by_identity
    end

    def self.normalize_access(value)
      return :rw if value.nil?

      symbol = value.to_sym
      unless %i[ro wo rw].include?(symbol)
        raise Plod::Error.new("invalid register access type '#{value}' (use :ro, :wo or :rw)", Loc.capture)
      end

      symbol
    end

    def size(value)
      @decl.size = value
    end

    def offset(value)
      @decl.offset = value
    end

    def type(value)
      @decl.access = self.class.normalize_access(value)
    end

    def seqn(value)
      @decl.seqn = value
    end

    def Field(name, lsb, size = 1)
      if lsb.is_a?(Range)
        size = lsb.last - lsb.first + 1
        lsb = lsb.first
      elsif lsb.is_a?(Array)
        size = lsb[1] - lsb[0] + 1
        lsb = lsb[0]
      end
      unless lsb.is_a?(Integer) && size.is_a?(Integer) && lsb >= 0 && size >= 1
        raise Plod::Error.new("invalid bit field '#{name}': use Field(:name, lsb, size) or Field(:name, lo..hi)",
                              Loc.capture)
      end

      @decl.fields << IR::RegFieldDecl.new(name: name.to_sym, lsb: lsb, size: size, loc: Loc.capture)
      nil
    end

    def enableIf(&block)
      @enable_if_proc = block
      nil
    end

    def Method(name, **args, &block)
      raise Plod::Error.new("register method '#{name}' requires a body", Loc.capture) if block.nil?

      args_list, ret_type = process_signature(args, "register method #{name}")
      decl_method = IR::MethodDecl.new(
        name: name.to_sym, args: args_list, ret_type: ret_type,
        body: [], abstract: false, loc: Loc.capture
      )
      @decl.methods << decl_method
      @method_procs[decl_method] = block
      nil
    end
  end

  class ComponentDeclContext < Slate
    include Types::Sugar
    include Types::BitSugar
    include DeclTypes

    attr_reader :decl, :method_procs

    def initialize(frontend, name, abstract:)
      @frontend = frontend
      @decl = IR::ComponentDecl.new(
        name: name, methods: [], fields: [], abstract: abstract, loc: Loc.capture
      )
      @abstract = abstract
      @method_procs = {}.compare_by_identity
    end

    def Method(name, **args, &block)
      raise Plod::Error.new("abstract struct method '#{name}' must not have a body", Loc.capture) if @abstract && block
      raise Plod::Error.new("struct method '#{name}' requires a body", Loc.capture) if !@abstract && block.nil?

      args_list, ret_type = process_signature(args, "method #{name}")
      decl_method = IR::MethodDecl.new(
        name: name.to_sym, args: args_list, ret_type: ret_type,
        body: @abstract ? nil : [], abstract: @abstract, loc: Loc.capture
      )
      @decl.methods << decl_method
      @method_procs[decl_method] = block if block
      nil
    end

    def Field(name, type)
      expect_type!(type, "field #{name}")
      @decl.fields << IR::FieldDecl.new(
        name: name.to_sym, type: type, init_args: [], abstract: false, loc: Loc.capture
      )
      nil
    end
  end

  class DeviceDeclContext < Slate
    include Types::Sugar
    include Types::BitSugar
    include DeclTypes

    attr_reader :decl, :register_ctxs, :method_procs, :lambda_procs, :ctor_proc

    def initialize(frontend, name)
      @frontend = frontend
      @decl = IR::DeviceDecl.new(
        name: name, registers: [], methods: [], fields: [], enums: [], consts: [],
        lambdas: [], ctor: nil, loc: Loc.capture
      )
      @register_ctxs = []
      @method_procs = {}.compare_by_identity
      @lambda_procs = {}.compare_by_identity
      @ctor_proc = nil
    end

    def Register(name, size: nil, offset: nil, type: :rw, seqn: nil, &block)
      check_dup(@decl.registers.map(&:name), name, 'register')
      reg_ctx = RegisterDeclContext.new(@frontend, name, { size: size, offset: offset, type: type, seqn: seqn })
      reg_ctx.instance_eval(&block) if block
      @decl.registers << reg_ctx.decl
      @register_ctxs << reg_ctx
      nil
    end

    def Method(name, **args, &block)
      raise Plod::Error.new("device method '#{name}' requires a body", Loc.capture) if block.nil?

      check_dup(@decl.methods.map(&:name), name, 'method')
      args_list, ret_type = process_signature(args, "device method #{name}")
      decl_method = IR::MethodDecl.new(
        name: name.to_sym, args: args_list, ret_type: ret_type,
        body: [], abstract: false, loc: Loc.capture
      )
      @decl.methods << decl_method
      @method_procs[decl_method] = block
      nil
    end

    def AbstractMethod(name, **args)
      check_dup(@decl.methods.map(&:name), name, 'method')
      args_list, ret_type = process_signature(args, "abstract method #{name}")
      @decl.methods << IR::MethodDecl.new(
        name: name.to_sym, args: args_list, ret_type: ret_type,
        body: nil, abstract: true, loc: Loc.capture
      )
      nil
    end

    def Field(name, type, *init_args)
      check_dup(@decl.fields.map(&:name), name, 'field')
      expect_type!(type, "field #{name}")
      init_args.each do |arg|
        if arg.is_a?(Integer) || arg.is_a?(String) || arg.is_a?(TrueClass) || arg.is_a?(FalseClass) || arg.is_a?(IR::LambdaDecl)
          next
        end

        raise Plod::Error.new("field #{name}: init arguments must be constants or Lambda, got #{arg.inspect}",
                              Loc.capture)
      end

      @decl.fields << IR::FieldDecl.new(
        name: name.to_sym, type: type, init_args: init_args, abstract: false, loc: Loc.capture
      )
      nil
    end

    def AbstractField(name, type)
      check_dup(@decl.fields.map(&:name), name, 'field')
      expect_type!(type, "abstract field #{name}")
      @decl.fields << IR::FieldDecl.new(
        name: name.to_sym, type: type, init_args: [], abstract: true, loc: Loc.capture
      )
      nil
    end

    def Enum(name, &block)
      check_dup(@decl.enums.map(&:name), name, 'enum')
      enum_decl = IR::EnumDecl.new(name: name.to_sym, values: {}, loc: Loc.capture)
      raise Plod::Error.new("enum #{name} requires a body", Loc.capture) if block.nil?

      EnumDeclContext.new(enum_decl).instance_eval(&block)
      @decl.enums << enum_decl
      nil
    end

    def Const(name, type, value)
      check_dup(@decl.consts.map(&:name), name, 'constant')
      expect_type!(type, "constant #{name}")
      unless value.is_a?(Integer) || value.is_a?(String) || value.is_a?(TrueClass) || value.is_a?(FalseClass)
        raise Plod::Error.new("constant #{name}: value must be an integer, string or boolean, got #{value.inspect}",
                              Loc.capture)
      end

      @decl.consts << IR::ConstDecl.new(name: name.to_sym, type: type, value: value, loc: Loc.capture)
      nil
    end

    def Lambda(**args, &block)
      raise Plod::Error.new('Lambda requires a body', Loc.capture) if block.nil?

      args_list, = process_signature(args, 'lambda')
      lambda_decl = IR::LambdaDecl.new(
        name: :"lambda_#{@decl.lambdas.size}", args: args_list, body: [], loc: Loc.capture
      )
      @decl.lambdas << lambda_decl
      @lambda_procs[lambda_decl] = block
      lambda_decl
    end

    def Constructor(**args, &block)
      raise Plod::Error.new('device already has a constructor', Loc.capture) if @ctor_proc

      raise Plod::Error.new('Constructor requires a body', Loc.capture) if block.nil?

      args_list, = process_signature(args, 'constructor')
      @decl.ctor = IR::CtorDecl.new(args: args_list, inits: [], body: [], loc: Loc.capture)
      @ctor_proc = block
      nil
    end

    private

    def check_dup(names, name, what)
      raise Plod::Error.new("duplicate #{what} '#{name}'", Loc.capture) if names.include?(name.to_sym)
    end
  end
end
