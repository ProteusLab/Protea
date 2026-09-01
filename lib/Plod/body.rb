# frozen_string_literal: true

require_relative 'slate'
require_relative 'env'
require_relative 'ir'
require_relative 'types'

module Plod
  class Expr < Slate
    attr_reader :ctx, :node

    def initialize(ctx, node)
      @ctx = ctx
      @node = node
    end

    def type = Plod::IR.node_type(@node)

    BINOPS = {
      :+ => :add, :- => :sub, :* => :mul, :/ => :div, :% => :rem,
      :| => :or, :& => :and, :^ => :xor, :<< => :shl, :>> => :shr,
      :== => :eq, :!= => :ne, :< => :lt, :<= => :le, :> => :gt, :>= => :ge
    }.freeze

    BINOPS.each do |ruby_op, ir_op|
      define_method(ruby_op) do |other|
        @ctx.binop(ir_op, self, other)
      end
    end

    def ~
      @ctx.unop(:not, self)
    end

    def [](index)
      @ctx.get_elem(self, index)
    end

    def []=(value)
      @ctx.assign(self, value)
    end

    def get(index)
      @ctx.get_elem(self, index)
    end

    def set(index, value)
      @ctx.set_elem(self, index, value)
      nil
    end

    def method_missing(name, *args, &block)
      @ctx.member_access(self, name, args, block)
    end

    def respond_to_missing?(_name, _include_private = false)
      true
    end
  end

  class RegExpr < Expr
    attr_reader :reg

    def initialize(ctx, reg)
      storage_type = if reg.seqn
                       Types::Array.new(Types::Bits.new(reg.size * 8), reg.seqn)
                     else
                       Types::Bits.new(reg.size * 8)
                     end
      super(ctx, IR::VarRef.new(name: reg.name, type: storage_type, loc: nil))
      @reg = reg
    end

    def []=(value)
      @ctx.assign(self, value)
    end

    def at(index)
      @ctx.get_elem(self, index)
    end

    def set(index, value)
      @ctx.set_elem(self, index, value)
      nil
    end

    def [](index)
      @ctx.get_elem(self, index)
    end

    def method_missing(name, *args)
      field = @reg.fields.find { |f| f.name == name }
      return @ctx.reg_field_expr(self, @reg, name) if field

      method_decl = @reg.methods.find { |m| m.name == name }
      return @ctx.reg_method_expr(self, @reg, method_decl, args) if method_decl

      raise Plod::Error.new(
        "unknown field or method '#{name}' for register #{@reg.name} " \
        "(fields: #{@reg.fields.map(&:name).join(', ')}; " \
        "methods: #{@reg.methods.map(&:name).join(', ')})", Loc.capture
      )
    end

    def respond_to_missing?(_name, _include_private = false)
      true
    end
  end

  class EnumExpr < Slate
    attr_reader :ctx, :enum

    def initialize(ctx, enum)
      @ctx = ctx
      @enum = enum
    end

    def method_missing(name, *_args)
      if @enum.values.key?(name)
        @ctx.enum_val_expr(@enum, name)
      else
        raise Plod::Error.new(
          "unknown enum value '#{name}' for enum #{@enum.name} " \
          "(available: #{@enum.values.keys.join(', ')})", Loc.capture
        )
      end
    end

    def respond_to_missing?(name, _include_private = false)
      @enum.values.key?(name)
    end
  end

  class ErrorExpr < Expr
    def initialize(ctx)
      super(ctx, nil)
    end

    def method_missing(*)
      self
    end

    def []=(*)
      nil
    end

    def respond_to_missing?(*)
      true
    end
  end

  class BodyContext < Slate
    include Types::Sugar
    include Types::BitSugar

    def initialize(frontend, env)
      @frontend = frontend
      @env = env
      @stmts = []
      @provisional = {}.compare_by_identity
      @open_if = nil
    end

    def loc = Loc.capture

    def emit(node)
      @stmts << node
      @open_if = node.kind == :if ? node : nil
      node
    end

    def binop(op, lhs, rhs)
      l = value_expr(lhs)
      r = value_expr(rhs)
      consume(l)
      consume(r)
      Expr.new(self, IR::BinOp.new(op: op, lhs: l.node, rhs: r.node,
                                   type: binop_type(op, l.node, r.node), loc: loc))
    end

    def unop(op, operand)
      o = value_expr(operand)
      consume(o)
      Expr.new(self, IR::UnOp.new(op: op, operand: o.node, type: o.node&.type, loc: loc))
    end

    def assign(target, value)
      v = value_expr(value)
      consume(v)
      node = target.node
      unless %i[var self regfield getelem getfield].include?(node&.kind)
        raise Plod::Error.new("cannot assign to #{node ? node.kind : 'unknown'} expression", loc)
      end

      emit(IR::Assign.new(target: node, value: v.node, loc: loc))
      nil
    end

    def get_elem(container, index)
      idx = value_expr(index)
      consume(container) if container.is_a?(Expr)
      consume(idx)
      Expr.new(self, IR::GetElem.new(container: container.node, index: idx.node,
                                     type: elem_type(container.node), loc: loc))
    end

    def set_elem(container, index, value)
      idx = value_expr(index)
      v = value_expr(value)
      consume(container) if container.is_a?(Expr)
      consume(idx)
      consume(v)
      emit(IR::SetElem.new(container: container.node, index: idx.node, value: v.node, loc: loc))
      nil
    end

    def reg_field_expr(reg_expr, reg, field_name)
      field = reg.fields.find { |f| f.name == field_name }
      Expr.new(self, IR::RegFieldRef.new(reg: reg_expr.node, field: field_name,
                                         type: Types::Field.new(field.size), loc: loc))
    end

    def reg_method_expr(reg_expr, _reg, method_decl, args)
      arg_exprs = args.map { |a| consume_value(a) }
      node = IR::MethodCall.new(
        recv: reg_expr.node, name: method_decl.name,
        args: arg_exprs.map(&:node), ret_type: method_decl.ret_type, loc: loc
      )
      provisional(node)
    end

    def enum_val_expr(enum, key)
      Expr.new(self, IR::GetEnumVal.new(enum: enum.name, key: key, type: Types::Int.new, loc: loc))
    end

    def member_access(recv_expr, name, args, _block)
      recv_node = recv_expr.node
      recv_type = Plod::IR.node_type(recv_node)
      consume(recv_expr)

      return late_bound_call(recv_expr, name, args, 'receiver has unknown type') if recv_type.nil?

      deref_type = recv_type.deref

      if deref_type.is_a?(Types::Named)
        component = @frontend.component(deref_type.id)
        if component.nil?
          return late_bound_call(recv_expr, name, args, "type '#{deref_type.name}' is not declared in this file")
        end

        field = component.fields.find { |f| f.name == name }
        unless field.nil?
          raise Plod::Error.new("field '#{name}' of #{component.name} does not take arguments", loc) unless args.empty?

          return Expr.new(self, IR::GetField.new(recv: recv_node, name: name, type: field.type, loc: loc))
        end

        method_decl = component.methods.find { |m| m.name == name }
        if method_decl
          arg_exprs = args.map { |a| consume_value(a) }
          node = IR::MethodCall.new(
            recv: recv_node, name: name,
            args: arg_exprs.map(&:node), ret_type: method_decl.ret_type, loc: loc
          )
          return provisional(node)
        end

        if component.abstract
          return late_bound_call(recv_expr, name, args,
                                 "'#{deref_type.name}' is abstract; '#{name}' is late-bound to the environment")
        end

        raise Plod::Error.new(
          "unknown member '#{name}' for struct #{component.name} " \
          "(fields: #{component.fields.map(&:name).join(', ')}; " \
          "methods: #{component.methods.map(&:name).join(', ')})", loc
        )
      end

      late_bound_call(recv_expr, name, args, "receiver type '#{recv_type.name}' has no declared members")
    end

    def late_bound_call(recv_expr, name, args, note)
      @frontend.note_late_bound(note, loc)
      arg_exprs = args.map { |a| consume_value(a) }
      node = IR::MethodCall.new(
        recv: recv_expr.node, name: name,
        args: arg_exprs.map(&:node), ret_type: nil, loc: loc
      )
      provisional(node)
    end

    def provisional(node)
      emit(IR::ExprStmt.new(expr: node, loc: node.loc))
      @provisional[node] = @stmts.size - 1
      Expr.new(self, node)
    end

    def consume(expr)
      consume_node(expr.node) if expr.is_a?(Expr) && expr.node
    end

    def consume_value(value)
      expr = value_expr(value)
      consume(expr)
      expr
    end

    def consume_node(node)
      return unless node.is_a?(Struct)

      idx = @provisional.delete(node)
      @stmts[idx] = nil if idx
      node.members.each do |m|
        v = node[m]
        if v.is_a?(Struct)
          consume_node(v)
        elsif v.is_a?(Array)
          v.each { |e| consume_node(e) if e.is_a?(Struct) }
        end
      end
    end

    def value_expr(value)
      case value
      when Expr then value
      when Integer then Expr.new(self, IR::Const.new(value: value, type: Types::Int.new, loc: loc))
      when String then Expr.new(self, IR::Const.new(value: value, type: Types::Str.new, loc: loc))
      when Struct then Expr.new(self, value)
      when Types::Base
        raise Plod::Error.new("type '#{value.name}' used where a value is expected", loc)
      when nil
        raise Plod::Error.new('nil used where a value is expected', loc)
      else
        raise Plod::Error.new("unsupported expression operand: #{value.inspect}", loc)
      end
    end

    def Let(name, type, value)
      expect_type!(type, "variable #{name}")
      v = value_expr(value)
      consume(v)
      emit(IR::VarDecl.new(name: name, type: type, loc: loc))
      emit(IR::Assign.new(target: IR::VarRef.new(name: name, type: type, loc: loc), value: v.node, loc: loc))
      @env.define(name, Binding.new(:var, nil, type: type))
      nil
    end

    def Var(name, type)
      expect_type!(type, "variable #{name}")
      emit(IR::VarDecl.new(name: name, type: type, loc: loc))
      @env.define(name, Binding.new(:var, nil, type: type))
      nil
    end

    def If(cond, &block)
      c = value_expr(cond)
      consume(c)
      node = IR::If.new(cond: c.node, then_body: sub_body(block).final_stmts, elsif_list: [], else_body: nil, loc: loc)
      emit(node)
      nil
    end

    def Elseif(cond, &block)
      unless @open_if
        raise Plod::Error.new('Elseif must directly follow an If (or another Elseif) at the same nesting level', loc)
      end

      c = value_expr(cond)
      consume(c)
      @open_if.elsif_list << [c.node, sub_body(block).final_stmts]
      nil
    end

    def Else(&block)
      unless @open_if
        raise Plod::Error.new('Else must directly follow an If (or Elseif) at the same nesting level', loc)
      end
      raise Plod::Error.new('this If already has an Else', loc) unless @open_if.else_body.nil?

      @open_if.else_body = sub_body(block).final_stmts
      @open_if = nil
      nil
    end

    def For(iter:, init:, to:, &block)
      from_e = value_expr(init)
      to_e = value_expr(to)
      consume(from_e)
      consume(to_e)
      iter_env = Env.new(@env)
      iter_env.define(iter, Binding.new(:var, nil, type: Types::Int.new))
      body = BodyContext.new(@frontend, iter_env)
      body.instance_eval(&block) if block
      node = IR::For.new(iter: iter, from: from_e.node, to: to_e.node, body: body.final_stmts, loc: loc)
      emit(node)
      nil
    end

    def Return(value = nil)
      v = value.nil? ? nil : consume_value(value).node
      emit(IR::Return.new(value: v, loc: loc))
      nil
    end

    def Cast(type, value)
      expect_type!(type, 'cast')
      v = value_expr(value)
      consume(v)
      Expr.new(self, IR::Cast.new(type: type, value: v.node, loc: loc))
    end

    def GetPtr(target)
      t = value_expr(target)
      consume(t)
      Expr.new(self, IR::GetPtr.new(target: t.node, type: Types::Ptr.new(Plod::IR.node_type(t.node)), loc: loc))
    end

    def this
      binding = @env.lookup(:__this__)
      return ErrorExpr.new(self) if binding.nil?

      Expr.new(self, binding.payload)
    end

    def sub_body(block)
      body = BodyContext.new(@frontend, Env.new(@env))
      body.instance_eval(&block) if block
      body
    end

    def expect_type!(value, what)
      return if value.is_a?(Types::Base)

      raise Plod::Error.new("#{what}: expected a type, got #{value.inspect}", loc)
    end

    def method_missing(name, *args)
      binding = @env.lookup(name)
      if binding
        case binding.kind
        when :var
          return Expr.new(self, IR::VarRef.new(name: name, type: binding.type, loc: loc))
        when :regfield, :self
          return Expr.new(self, binding.payload)
        when :reg
          return RegExpr.new(self, binding.payload)
        when :enum
          return EnumExpr.new(self, binding.payload)
        when :fn
          arg_exprs = args.map { |a| consume_value(a) }
          node = IR::Call.new(
            name: name, args: arg_exprs.map(&:node),
            ret_type: binding.payload.ret_type, loc: loc
          )
          return provisional(node)
        when :regfn
          method_decl, = binding.payload
          arg_exprs = args.map { |a| consume_value(a) }
          recv = IR::SelfRef.new(subject: :register, type: nil, loc: loc)
          node = IR::MethodCall.new(
            recv: recv, name: name,
            args: arg_exprs.map(&:node), ret_type: method_decl.ret_type, loc: loc
          )
          return provisional(node)
        end
      end

      type = @frontend.lookup_type(name)
      return type if type

      raise Plod::Error.new("unknown name '#{name}'#{@frontend.known_names_hint}", loc)
    end

    def respond_to_missing?(name, include_private = false)
      !@env.lookup(name).nil? || @frontend.type_declared?(name) || super
    end

    def final_stmts
      @stmts.compact
    end

    private

    def binop_type(op, lhs, rhs)
      return Types::Bool.new if %i[eq ne lt le gt ge].include?(op)

      lt = Plod::IR.node_type(lhs)
      rt = Plod::IR.node_type(rhs)
      return nil if lt.nil? || rt.nil?

      return lt if lt.named? || lt.is_a?(Types::Str)
      return rt if rt.named? || rt.is_a?(Types::Str)
      return lt unless lt.numeric? && rt.numeric?

      if lt.bits?
        rt.bits? && rt.size > lt.size ? rt : lt
      elsif rt.bits?
        rt
      else
        lt
      end
    end

    def elem_type(container_node)
      t = Plod::IR.node_type(container_node)
      return t.elem if t.is_a?(Types::Array)

      nil
    end
  end

  class CtorContext < BodyContext
    def initialize(frontend, env, ctor_decl)
      super(frontend, env)
      @ctor_decl = ctor_decl
    end

    def Init(field, *args)
      arg_exprs = args.map { |a| consume_value(a) }
      @ctor_decl.inits << IR::InitCall.new(field: field, args: arg_exprs.map(&:node), loc: loc)
      nil
    end

    def Body(&block)
      body = sub_body(block)
      @ctor_decl.body = body.final_stmts
      nil
    end
  end
end
