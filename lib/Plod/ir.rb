# frozen_string_literal: true

require_relative 'types'
require_relative 'diagnostics'

module Plod
  module IR
    def self.node(*members, kind: nil)
      Struct.new(*members, :loc, keyword_init: true) do
        define_method(:kind) { kind }
      end
    end

    VarRef = node :name, :type, kind: :var
    Const = node :value, :type, kind: :const
    SelfRef = node :subject, :type, kind: :self

    BinOp = node :op, :lhs, :rhs, :type, kind: :binop
    UnOp = node :op, :operand, :type, kind: :unop
    Cast = node :type, :value, kind: :cast
    RegFieldRef = node :reg, :field, :type, kind: :regfield
    GetField = node :recv, :name, :type, kind: :getfield
    GetElem = node :container, :index, :type, kind: :getelem
    SetElem = node :container, :index, :value, kind: :setelem
    GetEnumVal = node :enum, :key, :type, kind: :enumval
    GetPtr = node :target, :type, kind: :getptr
    MethodCall = node :recv, :name, :args, :ret_type, kind: :mcall
    Call = node :name, :args, :ret_type, kind: :call

    VarDecl = node :name, :type, kind: :vardecl
    Assign = node :target, :value, kind: :assign
    ExprStmt = node :expr, kind: :exprstmt
    If = node :cond, :then_body, :elsif_list, :else_body, kind: :if
    For = node :iter, :from, :to, :body, kind: :for
    Return = node :value, kind: :return
    InitCall = node :field, :args, kind: :initcall

    RegFieldDecl = node :name, :lsb, :size, kind: :regfielddecl
    EnumDecl = node :name, :values, kind: :enumdecl
    ConstDecl = node :name, :type, :value, kind: :constdecl
    FieldDecl = node :name, :type, :init_args, :abstract, kind: :fielddecl
    MethodDecl = node :name, :args, :ret_type, :body, :abstract, kind: :methoddecl
    LambdaDecl = node :name, :args, :body, kind: :lambdadecl
    RegisterDecl = node :name, :size, :offset, :access, :seqn, :fields, :methods, :enable_if, kind: :registerdecl
    CtorDecl = node :args, :inits, :body, kind: :ctordecl
    DeviceDecl = node :name, :registers, :methods, :fields, :enums, :consts, :lambdas, :ctor, kind: :devicedecl
    ComponentDecl = node :name, :methods, :fields, :abstract, kind: :componentdecl
    Program = node :path, :devices, :components, :objects, :functions, kind: :program

    KIND_TO_CLASS = {
      var: VarRef, const: Const, self: SelfRef,
      binop: BinOp, unop: UnOp, cast: Cast, regfield: RegFieldRef,
      getfield: GetField, getelem: GetElem, setelem: SetElem,
      enumval: GetEnumVal, getptr: GetPtr, mcall: MethodCall, call: Call,
      vardecl: VarDecl, assign: Assign, exprstmt: ExprStmt,
      if: If, for: For, return: Return, initcall: InitCall,
      regfielddecl: RegFieldDecl, enumdecl: EnumDecl, constdecl: ConstDecl,
      fielddecl: FieldDecl, methoddecl: MethodDecl, lambdadecl: LambdaDecl,
      registerdecl: RegisterDecl, ctordecl: CtorDecl,
      devicedecl: DeviceDecl, componentdecl: ComponentDecl, program: Program
    }.freeze

    def self.from_h(h)
      return nil if h.nil?

      klass = KIND_TO_CLASS[h[:kind]]
      raise ArgumentError, "unknown IR node kind: #{h[:kind].inspect}" if klass.nil?

      klass.from_h(h)
    end

    def self.node_type(node)
      return nil if node.nil?

      %i[call mcall].include?(node.kind) ? node.ret_type : node.type
    end

    TYPE_MEMBERS = %i[type ret_type].freeze

    module Serializable
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def from_h(h)
          kwargs = members.each_with_object({}) do |m, acc|
            next if m == :loc

            acc[m] = deserialize_member(m, h[m])
          end
          kwargs[:loc] = Plod::Loc.from_h(h[:loc]) unless h[:loc].nil?
          new(**kwargs)
        end

        def deserialize_member(name, value)
          if name == :elsif_list
            (value || []).map { |cond, body| [Plod::IR.from_h(cond), deserialize_stmts(body)] }
          elsif name == :values
            value.transform_keys(&:to_sym)
          elsif name == :objects
            value.to_h { |k, v| [k.to_sym, Plod::Types.from_h(v)] }
          elsif name == :functions
            value.to_h { |k, v| [k.to_sym, Plod::IR.from_h(v)] }
          elsif TYPE_MEMBERS.include?(name)
            Plod::Types.from_h(value)
          else
            deserialize_value(value)
          end
        end

        def deserialize_stmts(value)
          (value || []).map { |s| Plod::IR.from_h(s) }
        end

        def deserialize_value(value)
          if value.is_a?(Hash) && value.key?(:kind)
            Plod::IR.from_h(value)
          elsif value.is_a?(Array)
            value.map { |v| v.is_a?(Hash) && v.key?(:kind) ? Plod::IR.from_h(v) : v }
          elsif value.is_a?(Hash)
            value.transform_keys(&:to_sym)
          else
            value
          end
        end
      end

      def to_h
        members.each_with_object({ kind: kind }) do |m, acc|
          v = self[m]
          acc[m] = serialize_member(m, v) unless v.nil?
        end
      end

      private

      def serialize_member(name, v)
        if name == :elsif_list
          v.map { |cond, body| [cond.to_h, serialize_stmts(body)] }
        elsif name == :values
          v.transform_keys(&:to_sym)
        elsif name == :objects
          v.to_h { |k, t| [k.to_sym, t.to_h] }
        elsif name == :functions
          v.to_h { |k, m| [k.to_sym, m.to_h] }
        elsif TYPE_MEMBERS.include?(name)
          v.to_h
        else
          serialize_value(v)
        end
      end

      def serialize_stmts(stmts)
        stmts.map(&:to_h)
      end

      def serialize_value(v)
        if v.is_a?(Plod::Types::Base) || v.is_a?(Plod::Loc) ||
           (v.is_a?(Struct) && v.respond_to?(:kind))
          v.to_h
        elsif v.is_a?(Array)
          v.map { |e| serialize_value(e) }
        elsif v.is_a?(Hash)
          v.transform_values { |e| serialize_value(e) }
        else
          v
        end
      end
    end

    KIND_TO_CLASS.each_value { |k| k.include(Serializable) }

    SIGNATURE_CLASSES = [MethodDecl, LambdaDecl, CtorDecl].freeze

    module SignatureArgsClassSide
      def deserialize_member(name, value)
        return (value || []).map { |n, t| [n.to_sym, t.nil? ? nil : Plod::Types.from_h(t)] } if name == :args

        super
      end
    end

    module SignatureArgsInstanceSide
      def serialize_member(name, v)
        return v.map { |n, t| [n, t&.to_h] } if name == :args

        super
      end
    end

    SIGNATURE_CLASSES.each do |k|
      k.singleton_class.prepend(SignatureArgsClassSide)
      k.prepend(SignatureArgsInstanceSide)
    end
  end
end
