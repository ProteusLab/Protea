# frozen_string_literal: true

require_relative 'diagnostics'
require_relative 'env'
require_relative 'ir'
require_relative 'types'
require_relative 'body'
require_relative 'decl'

module Plod
  class Frontend
    attr_reader :program, :diag, :file_env

    def initialize
      @program = IR::Program.new(path: nil, devices: [], components: [], objects: {}, functions: {})
      @diag = DiagnosticBag.new
      @components = {}
      @file_env = Env.new
      @device_ctors = {}.compare_by_identity
    end

    def self.load_file(path)
      frontend = new
      frontend.load_file(path)
      frontend
    end

    def self.load_source(source, path = '(source)')
      frontend = new
      frontend.load_source(source, path)
      frontend
    end

    def load_file(path)
      load_source(File.read(path), path.to_s)
    end

    def load_source(source, path)
      @program.path = path
      file_context = FileContext.new(self)
      safely(path) { file_context.instance_eval(source, path) }
      evaluate_program!
      @program
    end

    def component(name)
      @components[name.to_sym]
    end

    def lookup_type(name)
      Types::Named.new(name) if @components.key?(name.to_sym)
    end

    def type_declared?(name)
      @components.key?(name.to_sym)
    end

    def known_names_hint
      names = (@components.keys + @program.objects.keys).take(8)
      names.empty? ? '' : " (known types and objects: #{names.join(', ')}, ...)"
    end

    def note_late_bound(note, loc)
      @diag.warning("late-bound call: #{note}", loc)
    end

    def register_component(decl)
      name = decl.name
      if @components.key?(name) || @program.devices.any? { |d| d.name == name }
        raise Plod::Error.new("duplicate declaration of '#{name}'", decl.loc)
      end

      @components[name] = decl
      @program.components << decl
    end

    def register_device(decl)
      if @program.devices.any? { |d| d.name == decl.name } || @components.key?(decl.name)
        raise Plod::Error.new("duplicate declaration of '#{decl.name}'", decl.loc)
      end

      @program.devices << decl
    end

    def register_object(name, type, loc)
      if @program.objects.key?(name) || @file_env.defined_here?(name)
        raise Plod::Error.new("duplicate abstract object '#{name}'", loc)
      end

      @program.objects[name] = type
      @file_env.define(name, Binding.new(:var, nil, type: type))
      nil
    end

    def register_function(decl)
      raise Plod::Error.new("duplicate abstract method '#{decl.name}'", decl.loc) if @file_env.defined_here?(decl.name)

      @program.functions[decl.name] = decl
      @file_env.define(decl.name, Binding.new(:fn, decl))
      nil
    end

    def device_ctor_proc(device_decl)
      @device_ctors[device_decl]
    end

    def register_ctor_proc(device_decl, proc)
      @device_ctors[device_decl] = proc
    end

    def method_proc(method_decl)
      @method_procs ||= {}.compare_by_identity
      @method_procs[method_decl]
    end

    def register_method_proc(method_decl, proc)
      @method_procs ||= {}.compare_by_identity
      @method_procs[method_decl] = proc
    end

    def lambda_proc(lambda_decl)
      @lambda_procs ||= {}.compare_by_identity
      @lambda_procs[lambda_decl]
    end

    def register_lambda_proc(lambda_decl, proc)
      @lambda_procs ||= {}.compare_by_identity
      @lambda_procs[lambda_decl] = proc
    end

    def enable_if_proc(register_decl)
      @enable_if_procs ||= {}.compare_by_identity
      @enable_if_procs[register_decl]
    end

    def register_enable_if_proc(register_decl, proc)
      @enable_if_procs ||= {}.compare_by_identity
      @enable_if_procs[register_decl] = proc
    end

    private

    def safely(where)
      yield
    rescue Plod::Error => e
      @diag.error(e.message, e.diagnostic.loc)
    rescue StandardError => e
      @diag.error("internal error while processing #{where}: #{e.class}: #{e.message}", nil)
    end

    def evaluate_program!
      @program.components.each { |c| eval_component(c) }
      @program.devices.each { |d| eval_device(d) }
    end

    def eval_component(component)
      env = Env.new(@file_env)
      component.fields.each { |f| env.define(f.name, Binding.new(:var, nil, type: f.type)) }
      # rubocop:disable Style/CombinableLoops -- two passes by design: every method must be
      # defined in env before any body evaluates, since bodies may reference later methods
      component.methods.each { |m| env.define(m.name, Binding.new(:fn, m)) }

      component.methods.each do |m|
        next if m.abstract

        body_env = Env.new(env)
        m.args.each { |n, t| body_env.define(n, Binding.new(:var, nil, type: t)) }
        ctx = BodyContext.new(self, body_env)
        safely("method #{component.name}.#{m.name}") { ctx.instance_eval(&method_proc(m)) }
        m.body = ctx.final_stmts
      end
      # rubocop:enable Style/CombinableLoops
    end

    def eval_device(device)
      device_env = build_device_env(device)

      device.methods.each do |m|
        next if m.abstract

        body_env = Env.new(device_env)
        m.args.each { |n, t| body_env.define(n, Binding.new(:var, nil, type: t)) }
        ctx = BodyContext.new(self, body_env)
        safely("method #{device.name}.#{m.name}") { ctx.instance_eval(&method_proc(m)) }
        m.body = ctx.final_stmts
      end

      device.registers.each { |r| eval_register(device, device_env, r) }

      device.lambdas.each do |l|
        body_env = Env.new(device_env)
        l.args.each { |n, t| body_env.define(n, Binding.new(:var, nil, type: t)) }
        ctx = BodyContext.new(self, body_env)
        safely("lambda #{device.name}.#{l.name}") { ctx.instance_eval(&lambda_proc(l)) }
        l.body = ctx.final_stmts
      end

      eval_ctor(device, device_env)
    end

    def build_device_env(device)
      env = Env.new(@file_env)
      device.registers.each { |r| env.define(r.name, Binding.new(:reg, r)) }
      device.fields.each { |f| env.define(f.name, Binding.new(:var, nil, type: f.type)) }
      device.consts.each { |c| env.define(c.name, Binding.new(:var, nil, type: c.type)) }
      device.enums.each { |e| env.define(e.name, Binding.new(:enum, e)) }
      device.methods.each { |m| env.define(m.name, Binding.new(:fn, m)) }
      env.define(:__this__, Binding.new(:self, IR::SelfRef.new(subject: :device, type: nil, loc: device.loc)))
      env
    end

    def eval_register(device, device_env, reg)
      reg_env = Env.new(device_env)
      self_ref = IR::SelfRef.new(subject: :register, type: Types::Bits.new(reg.size * 8), loc: reg.loc)
      reg.fields.each do |f|
        field_ref = IR::RegFieldRef.new(reg: self_ref, field: f.name, type: Types::Field.new(f.size), loc: f.loc)
        reg_env.define(f.name, Binding.new(:regfield, field_ref))
      end
      reg.methods.each { |m| reg_env.define(m.name, Binding.new(:regfn, [m])) }
      reg_env.define(:__this__, Binding.new(:self, self_ref))

      reg.methods.each do |m|
        body_env = Env.new(reg_env)
        m.args.each { |n, t| body_env.define(n, Binding.new(:var, nil, type: t)) }
        ctx = BodyContext.new(self, body_env)
        safely("method #{device.name}.#{reg.name}.#{m.name}") { ctx.instance_eval(&method_proc(m)) }
        m.body = ctx.final_stmts
      end

      return if enable_if_proc(reg).nil?

      ctx = BodyContext.new(self, Env.new(reg_env))
      result = safely("enableIf of #{device.name}.#{reg.name}") { ctx.instance_eval(&enable_if_proc(reg)) }
      stmts = ctx.final_stmts
      if result.is_a?(Expr)
        reg.enable_if = result.node
      elsif stmts.size == 1 && stmts.first.kind == :exprstmt
        reg.enable_if = stmts.first.expr
      else
        @diag.error("enableIf of #{device.name}.#{reg.name} must be a single boolean expression", reg.loc)
      end
    end

    def eval_ctor(device, device_env)
      ctor = device.ctor
      proc = device_ctor_proc(device)
      return if ctor.nil? && proc.nil?
      return @diag.error("constructor state is inconsistent for #{device.name}", device.loc) if ctor.nil? || proc.nil?

      ctor_env = Env.new(device_env)
      ctor.args.each { |n, t| ctor_env.define(n, Binding.new(:var, nil, type: t)) }
      ctx = CtorContext.new(self, ctor_env, ctor)
      safely("constructor of #{device.name}") { ctx.instance_eval(&proc) }
    end

    class FileContext < Slate
      include Types::Sugar
      include Types::BitSugar
      include DeclTypes

      def initialize(frontend)
        @frontend = frontend
      end

      def Device(name, &block)
        raise Plod::Error.new("Device #{name} requires a body", Loc.capture) if block.nil?

        ctx = DeviceDeclContext.new(@frontend, name)
        ctx.instance_eval(&block)
        register_device_procs(ctx)
        @frontend.register_device(ctx.decl)
        nil
      end

      def Struct(name, &block)
        raise Plod::Error.new("Struct #{name} requires a body", Loc.capture) if block.nil?

        ctx = ComponentDeclContext.new(@frontend, name, abstract: false)
        ctx.instance_eval(&block)
        register_component_procs(ctx)
        @frontend.register_component(ctx.decl)
        nil
      end

      def AbstractStruct(name, &block)
        ctx = ComponentDeclContext.new(@frontend, name, abstract: true)
        ctx.instance_eval(&block) if block
        register_component_procs(ctx)
        @frontend.register_component(ctx.decl)
        nil
      end

      def AbstractObject(name, type)
        expect_type!(type, "abstract object #{name}")
        @frontend.register_object(name.to_sym, type, Loc.capture)
        nil
      end

      def AbstractMethod(name, **args)
        args_list, ret_type = process_signature(args, "abstract method #{name}")
        decl = IR::MethodDecl.new(
          name: name.to_sym, args: args_list, ret_type: ret_type,
          body: nil, abstract: true, loc: Loc.capture
        )
        @frontend.register_function(decl)
        nil
      end

      private

      def register_device_procs(ctx)
        ctx.register_ctxs.each do |reg_ctx|
          reg_ctx.decl.methods.each { |m| @frontend.register_method_proc(m, reg_ctx.method_procs[m]) }
          @frontend.register_enable_if_proc(reg_ctx.decl, reg_ctx.enable_if_proc)
        end
        ctx.decl.methods.each { |m| @frontend.register_method_proc(m, ctx.method_procs[m]) }
        ctx.decl.lambdas.each { |l| @frontend.register_lambda_proc(l, ctx.lambda_procs[l]) }
        @frontend.register_ctor_proc(ctx.decl, ctx.ctor_proc)
      end

      def register_component_procs(ctx)
        ctx.decl.methods.each { |m| @frontend.register_method_proc(m, ctx.method_procs[m]) }
      end
    end
  end
end
