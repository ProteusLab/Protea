# frozen_string_literal: true

module Plod
  class Checker
    private

    def check_checkpoint(device)
      checkpoint = device.checkpoint
      return unless checkpoint

      device.methods.each do |method|
        if %i[serialize unserialize].include?(method.name)
          error('Checkpoint conflicts with handwritten serialize/unserialize methods', method)
        end
      end
      if checkpoint.entries.any? { |entry| entry.kind == :checkpointinherit } && checkpoint.entries.size != 1
        error('Inherit must be the only checkpoint entry', checkpoint)
      end
      ctx = TypeContext.new(self, device_env(device), nil, device: device)
      check_checkpoint_entries(checkpoint.entries, ctx, device, {}, [])
    end

    def check_checkpoint_entries(entries, ctx, device, keys, temporaries)
      entries.each do |entry|
        case entry.kind
        when :checkpointvalue
          check_checkpoint_key(entry.key, ctx, keys)
          type = ctx.expr_type(entry.destination)
          check_checkpoint_destination(entry.destination, ctx, temporaries)
          valid = if entry.encoding == :scalar
                    checkpoint_scalar?(type)
                  elsif entry.encoding == :array
                    (type.is_a?(Types::Array) || type.is_a?(Types::Vector)) && checkpoint_scalar?(type.elem)
                  end
          error('unsupported checkpoint value type or encoding', entry) unless valid
        when :checkpointrepeat
          type = ctx.expr_type(entry.count)
          error('checkpoint Repeat count must be numeric', entry) unless type&.numeric?
          if entry.count.kind == :const && entry.count.value.is_a?(Integer) && entry.count.value.negative?
            error('checkpoint Repeat count cannot be negative', entry)
          end
          if ctx.lookup(entry.iter) || !entry.iter.to_s.match?(/\A[a-z_]\w*\z/) ||
             entry.iter.to_s.start_with?('_plod_') || entry.iter == :cp
            error('checkpoint Repeat requires a local index name without shadowing', entry)
          end
          ctx.scoped do
            ctx.define_local(entry.iter, Types::Int.new)
            check_checkpoint_entries(entry.entries, ctx, device, keys, temporaries)
          end
        when :checkpointmap
          check_checkpoint_map(entry, ctx, device, keys, temporaries)
        when :checkpointdelegate
          check_checkpoint_delegate(entry, ctx, temporaries)
        when :checkpointhook
          method = device.methods.find { |m| m.name == entry.name }
          unless method && !method.abstract && method.args.empty? && method.ret_type.nil?
            error('AfterRestore requires a concrete zero-argument void device method', entry)
          end
        when :checkpointinherit
          nil
        else
          error('Checkpoint accepts only declarative checkpoint entries', entry)
        end
      end
    end

    def checkpoint_scalar?(type)
      type && (type.numeric? || type.boolean? || type.is_a?(Types::Str)) && (!type.bits? || type.size <= 64)
    end

    def check_checkpoint_key(key, ctx, keys)
      error('checkpoint key must be a string', key) unless ctx.expr_type(key).is_a?(Types::Str)
      return unless key.kind == :const && key.value.is_a?(String)

      error("duplicate checkpoint key '#{key.value}'", key) if keys[key.value]
      keys[key.value] = true
    end

    def check_checkpoint_destination(node, ctx, temporaries)
      valid = case node.kind
              when :var
                %i[field reg].include?(ctx.lookup(node.name)&.first) || temporaries.include?(node.name)
              when :getfield
                !IR.node_type(node.recv).is_a?(Types::Ptr) &&
                check_checkpoint_destination(node.recv, ctx, temporaries)
              when :getelem
                check_checkpoint_destination(node.container, ctx, temporaries)
              when :mcall
                type = IR.node_type(node.recv)
                node.name == :at && node.args.size == 1 &&
                (type.is_a?(Types::Array) || type.is_a?(Types::Vector)) &&
                check_checkpoint_destination(node.recv, ctx, temporaries)
              else
                false
              end
      error('checkpoint destination must be writable device storage', node) unless valid
      valid
    end

    def check_checkpoint_map(entry, ctx, device, keys, temporaries)
      check_checkpoint_key(entry.key, ctx, keys)
      type = ctx.expr_type(entry.destination)
      check_checkpoint_destination(entry.destination, ctx, temporaries)
      unless type.is_a?(Types::Map) && entry.count_type.is_a?(Types::Bits) && entry.count_type.size <= 64
        error('OrderedMap requires a map and a bit-vector CountType of at most 64 bits', entry)
        return
      end
      names = [entry.iter, entry.key_name, entry.value_name]
      if names.uniq.size != 3 || names.any? do |name|
           ctx.lookup(name) || !name.to_s.match?(/\A[a-z_]\w*\z/) || name.to_s.start_with?('_plod_') || name == :cp
         end
        error('OrderedMap bindings must be distinct local names without shadowing', entry)
      end
      ctx.scoped do
        ctx.define_local(entry.iter, Types::Int.new)
        ctx.define_local(entry.key_name, type.key)
        ctx.define_local(entry.value_name, type.elem)
        check_checkpoint_entries(entry.entries, ctx, device, keys, temporaries + [entry.key_name, entry.value_name])
      end
    end

    def check_checkpoint_delegate(entry, ctx, temporaries)
      type = ctx.expr_type(entry.destination)
      check_checkpoint_destination(entry.destination, ctx, temporaries)
      error('checkpoint Delegate prefix must be a string', entry) unless ctx.expr_type(entry.prefix).is_a?(Types::Str)
      component = type.is_a?(Types::Named) && @components[type.id]
      valid = component && %i[serialize unserialize].all? do |name|
        method = component.methods.find { |m| m.name == name }
        cp = name == :serialize ? :CheckpointOut : :CheckpointIn
        method && method.ret_type.nil? && method.args.size == 2 &&
          method.args.first.last.is_a?(Types::Str) && method.args.last.last.is_a?(Types::Ref) &&
          method.args.last.last.stored == Types::Named.new(cp) && (name != :serialize || method.const)
      end
      error('Delegate requires serialize(prefix, cp) const and unserialize(prefix, cp)', entry) unless valid
    end
  end
end
