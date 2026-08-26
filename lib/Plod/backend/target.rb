# frozen_string_literal: true

require 'yaml'

module Plod
  module Backend
    class Target
      ATTRS = %i[name devices base ctor_base_args includes forward_decls port_body init_body env].freeze

      attr_reader(*ATTRS)

      def self.load(path)
        data = Plod.yaml_load_file(path)
        from_h(data, path)
      end

      def self.from_h(raw, path = nil)
        data = raw.transform_keys(&:to_sym)
        unknown = data.keys - ATTRS
        raise Plod::Error.new("target #{path}: unknown keys #{unknown.join(', ')}") unless unknown.empty?

        target = new
        target.instance_variable_set(:@name, data[:name] || File.basename(path.to_s, '.yaml'))
        target.instance_variable_set(:@devices, (data[:devices] || []).map(&:to_sym))
        target.instance_variable_set(:@base, data[:base])
        target.instance_variable_set(:@ctor_base_args, data[:ctor_base_args] || 'params')
        target.instance_variable_set(:@includes, data[:includes] || [])
        target.instance_variable_set(:@forward_decls, data[:forward_decls] || [])
        target.instance_variable_set(:@port_body, data[:port_body] || "return #{data[:base]}::getPort(if_name, idx);")
        target.instance_variable_set(:@init_body, data[:init_body] || "#{data[:base]}::init();")
        target.instance_variable_set(:@env, data[:env] || {})
        target.validate!(path)
        target
      end

      def validate!(path)
        where = "target #{path || name}"
        raise Plod::Error.new("#{where}: 'base' is required") if @base.nil? || @base.empty?
        raise Plod::Error.new("#{where}: 'base' must be a string") unless @base.is_a?(String)
      end

      def supports_device?(device_name)
        @devices.empty? || @devices.include?(device_name.to_sym)
      end

      def env_rewrite(name)
        @env[name.to_s] || @env[name.to_sym]
      end

      class Registry
        def initialize(paths)
          @targets = {}
          paths.each do |dir|
            Dir[File.join(dir, '*.yaml')].sort.each do |file|
              target = Target.load(file)
              @targets[target.name.to_s] = target
            end
          end
        end

        def [](name)
          @targets[name.to_s]
        end

        def all
          @targets.values
        end

        def for_device(device_name)
          all.find { |t| t.devices.include?(device_name.to_sym) }
        end
      end
    end
  end
end
