# frozen_string_literal: true

# Main module of Protea
module Protea
  # Value class is a super class of Variable or Constant.
  module Type
    # Base module for every type
    module TypeObject end

    # TODO
    module EmptyInterface end

    def self.TypeObject(type_name, *fields_with_inter)
      interface = EmptyInterface

      if fields_with_inter.last.is_a?(Module)
        interface = fields_with_inter.last
        fields_with_inter.pop
      end

      ret_class = Class.new(Struct.new(*fields_with_inter)) do
        include TypeObject

        define_method(:name) do
          field_names = {}

          to_h.each do |key, value|
            field_names[key] = value.to_s
          end

          type_name = type_name.to_s
          (type_name % field_names).to_sym
        end

        define_method(:to_s) do
          name
        end

        define_method(:inject) do |var|
          var.extend(interface)
        end

        define_method(:inter) do
          interface
        end
      end

      ret_class
    end

    # Empty type for ADL var
    Empty = TypeObject(:empty)

    # TODO
    module IntInter
      def %(other)
        scope.rem(self, other)
      end
    end

    # Just Int
    Int = TypeObject(:int, IntInter)

    # Empty type for ADL var
    Lambda = TypeObject(:lambda)

    # TODO
    module ArrayInter
      def get(index)
        scope.get_container_element(plod_type.stored_type, self, index)
      end

      def set(index, value)
        scope.stmt(:set, [self, index, value])
      end
    end

    Array = TypeObject('%{stored_type}[%{size}]', :stored_type, :size, ArrayInter)

    # Analogue of array
    Bitvector = TypeObject('b%{size}', :size)

    Regfield = TypeObject('rf%{size}', :size)

    String = TypeObject('str')

    Auto = TypeObject('auto')

    class Ptr
      include TypeObject

      def initialize(stored_type)
        @stored_type = stored_type
      end

      def name
        "ptr(#{@stored_type.name})".to_s
      end

      def to_s
        name
      end

      def inter
        @stored_type.inter
      end

      def inject(var)
        var.extend(inter)
      end
    end

    class Ref
      include TypeObject

      def initialize(stored_type)
        @stored_type = stored_type
      end

      def name
        "ref(#{@stored_type.name})".to_s
      end

      def to_s
        name
      end

      def inter
        @stored_type.inter
      end

      def inject(var)
        var.extend(inter)
      end
    end

    module BoolInter
    end

    Bool = TypeObject('bool', BoolInter)

    # TODO
    module Utils
      def Array(type, size)
        Type::Array.new(type, size)
      end

      def Int
        Type::Int.new
      end

      def Ptr(type)
        Type::Ptr.new(type)
      end

      def Ref(type)
        Type::Ref.new(type)
      end

      def Bool
        Type::Bool.new
      end

      def String
        Type::String.new
      end

      def Auto
        Type::Auto.new
      end

      def method_missing(name)
        if name.start_with?("B")
          size = name[1..].to_i
          Type::Bitvector.new(size)
        else
          raise "Bad type: #{name}"
        end
      end
    end
  end
end
