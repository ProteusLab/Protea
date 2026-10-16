# frozen_string_literal: true

require_relative 'body'

module Plod
  # Checkpoint entries describe both directions; they are not procedural bodies.
  class CheckpointContext < BodyContext
    def Scalar(key, destination)
      checkpoint_value(key, destination, :scalar)
    end

    def Array(key, destination)
      checkpoint_value(key, destination, :array)
    end

    def Repeat(iter, count, &block)
      raise Plod::Error.new('Repeat requires a body', loc) unless block

      count_node = consume_value(count).node
      env = Env.new(@env)
      env.define(iter, Binding.new(:var, nil, type: Types::Int.new))
      body = CheckpointContext.new(@frontend, env)
      body.focus_eval(&block)
      emit(IR::CheckpointRepeat.new(iter: iter.to_sym, count: count_node, entries: body.final_stmts, loc: loc))
    end

    def OrderedMap(destination, **options, &block)
      raise Plod::Error.new('OrderedMap requires a body', loc) unless block

      count, count_type, iter, key, value = checkpoint_options(options, %i[Count CountType Iter Key Value])
      dest = consume_value(destination).node
      type = IR.node_type(dest)
      raise Plod::Error.new('OrderedMap requires a map destination', loc) unless type.is_a?(Types::Map)

      env = Env.new(@env)
      env.define(iter, Binding.new(:var, nil, type: Types::Int.new))
      env.define(key, Binding.new(:var, nil, type: type.key))
      env.define(value, Binding.new(:var, nil, type: type.elem))
      body = CheckpointContext.new(@frontend, env)
      body.focus_eval(&block)
      emit(IR::CheckpointMap.new(destination: dest, key: consume_value(count).node, count_type: count_type,
                                 iter: iter.to_sym, key_name: key.to_sym, value_name: value.to_sym,
                                 entries: body.final_stmts, loc: loc))
    end

    def Delegate(destination, **options)
      prefix, = checkpoint_options(options, [:Prefix])
      emit(IR::CheckpointDelegate.new(destination: consume_value(destination).node,
                                      prefix: consume_value(prefix).node, loc: loc))
    end

    def Inherit
      emit(IR::CheckpointInherit.new(loc: loc))
    end

    def AfterRestore(*names)
      names.each { |name| emit(IR::CheckpointHook.new(name: name.to_sym, loc: loc)) }
    end

    private

    def checkpoint_options(options, keys)
      raise Plod::Error.new("checkpoint options must be #{keys.join(', ')}", loc) unless options.keys.sort == keys.sort

      options.values_at(*keys)
    end

    def checkpoint_value(key, destination, encoding)
      emit(IR::CheckpointValue.new(key: consume_value(key).node, destination: consume_value(destination).node,
                                   encoding: encoding, loc: loc))
    end
  end
end
