# frozen_string_literal: true

module Plod
  module Types
    class Base
      def name = raise NotImplementedError

      def to_s = name

      def inspect = "#{self.class.name.split('::').last}(#{name})"

      def ==(other) = other.class == self.class && other.name == name
      alias eql? ==

      def hash = [self.class, name].hash

      def kind = self.class.kind

      def self.kind = name.split('::').last.downcase.to_sym

      def ptr? = false

      def ref? = false

      def bits? = false

      def field? = false

      def array? = false

      def named? = false

      def numeric? = false

      def boolean? = false

      def void? = false

      def deref
        self
      end

      def to_h = { kind: kind }

      def self.from_h(h) = raise NotImplementedError
    end

    class Int < Base
      def name = 'int'

      def numeric? = true

      def self.from_h(_h) = new
    end

    class Bool < Base
      def name = 'bool'

      def boolean? = true

      def numeric? = true

      def self.from_h(_h) = new
    end

    class Str < Base
      def name = 'str'

      def self.from_h(_h) = new
    end

    class Lambda < Base
      def name = 'lambda'

      def self.from_h(_h) = new
    end

    class Auto < Base
      def name = 'auto'

      def self.from_h(_h) = new
    end

    class Void < Base
      def name = 'void'

      def void? = true

      def self.from_h(_h) = new
    end

    class Bits < Base
      attr_reader :size

      def initialize(size)
        raise ArgumentError, "bit vector size must be positive, got #{size}" unless size.is_a?(Integer) && size.positive?

        @size = size
      end

      def name = "b#{@size}"

      def bits? = true

      def numeric? = true

      def to_h = { kind: kind, size: @size }

      def self.from_h(h) = new(h[:size])
    end

    class Field < Base
      attr_reader :size

      def initialize(size)
        raise ArgumentError, "register field size must be positive, got #{size}" unless size.is_a?(Integer) && size.positive?

        @size = size
      end

      def name = "rf#{@size}"

      def field? = true

      def bits? = true

      def numeric? = true

      def to_h = { kind: kind, size: @size }

      def self.from_h(h) = new(h[:size])
    end

    class Array < Base
      attr_reader :elem, :size

      def initialize(elem, size)
        raise ArgumentError, "array size must be positive, got #{size}" unless size.is_a?(Integer) && size.positive?
        raise ArgumentError, "array element type required" unless elem.is_a?(Base)

        @elem = elem
        @size = size
      end

      def name = "#{@elem.name}[#{@size}]"

      def array? = true

      def to_h = { kind: kind, elem: @elem.to_h, size: @size }

      def self.from_h(h) = new(Types.from_h(h[:elem]), h[:size])
    end

    module PointerLike
      def ptr? = is_a?(Ptr)

      def ref? = is_a?(Ref)

      def deref = @stored

      def stored = @stored
    end

    class Ptr < Base
      include PointerLike

      attr_reader :stored

      def initialize(stored)
        raise ArgumentError, 'pointer target type required' unless stored.is_a?(Base)

        @stored = stored
      end

      def name = "ptr(#{@stored.name})"

      def to_h = { kind: kind, stored: @stored.to_h }

      def self.from_h(h) = new(Types.from_h(h[:stored]))
    end

    class Ref < Base
      include PointerLike

      attr_reader :stored

      def initialize(stored)
        raise ArgumentError, 'reference target type required' unless stored.is_a?(Base)

        @stored = stored
      end

      def name = "ref(#{@stored.name})"

      def to_h = { kind: kind, stored: @stored.to_h }

      def self.from_h(h) = new(Types.from_h(h[:stored]))
    end

    class Named < Base
      attr_reader :id

      def initialize(id)
        raise ArgumentError, 'named type identifier required' if id.nil? || id.to_s.empty?

        @id = id.to_sym
      end

      def name = @id.to_s

      def named? = true

      def to_h = { kind: kind, id: @id }

      def self.from_h(h) = new(h[:id])
    end

    CLASSES = {
      int: Int, bool: Bool, str: Str, lambda: Lambda, auto: Auto, void: Void,
      bits: Bits, field: Field, array: Array, ptr: Ptr, ref: Ref, named: Named
    }.freeze

    def self.from_h(h)
      return nil if h.nil?

      klass = CLASSES[h[:kind].to_sym]
      raise ArgumentError, "unknown type kind: #{h[:kind]}" if klass.nil?

      klass.from_h(h)
    end

    module Sugar
      INT = Types::Int.new.freeze
      BOOL = Types::Bool.new.freeze
      STRING = Types::Str.new.freeze
      LAMBDA = Types::Lambda.new.freeze
      AUTO = Types::Auto.new.freeze

      def Int = INT

      def Bool = BOOL

      def String = STRING

      def Auto = AUTO

      def B(size) = Types::Bits.new(size)

      def Ptr(type) = Types::Ptr.new(type)

      def Ref(type) = Types::Ref.new(type)

      def Array(type, size) = Types::Array.new(type, size)
    end

    MAX_BITS = 4096

    module BitSugar
      (1..MAX_BITS).each do |n|
        define_method("B#{n}") { Types::Bits.new(n) }
      end
    end
  end
end
