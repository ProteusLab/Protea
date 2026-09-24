# frozen_string_literal: true

module Plod
  class Binding
    KINDS = %i[var regfield self reg enum fn regfn].freeze

    attr_reader :kind, :payload, :type

    def initialize(kind, payload = nil, type: nil)
      raise ArgumentError, "unknown binding kind: #{kind}" unless KINDS.include?(kind)

      @kind = kind
      @payload = payload
      @type = type
    end
  end

  class Env
    def initialize(parent = nil)
      @parent = parent
      @bindings = {}
    end

    def define(name, binding)
      @bindings[name.to_sym] = binding
    end

    def define_local(name, type = nil)
      define(name, Binding.new(:var, nil, type))
    end

    def lookup(name)
      @bindings[name.to_sym] || @parent&.lookup(name.to_sym)
    end

    def defined_here?(name)
      @bindings.key?(name.to_sym)
    end
  end
end
