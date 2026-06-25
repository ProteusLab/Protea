# lira/arch_ser_yaml.rb
require 'yaml'
require_relative 'ir'
require_relative 'arch'

module Lira
  module ArchSerYaml
    module_function

    def to_serializable(obj)
      case obj
      when nil
        nil
      when StatementSeq
        IrSerTxt.serialize_statement_seq(obj)
      when Array
        obj.map { |item| to_serializable(item) }
      when Hash
        obj.transform_keys(&:to_s).transform_values { |v| to_serializable(v) }
      else
        if obj.respond_to?(:to_h)
          obj.to_h.transform_keys(&:to_s).transform_values { |v| to_serializable(v) }
        else
          obj
        end
      end
    end

    def from_serializable(klass, data, item_class = nil)
      if klass == Array
        if item_class
          return data.map { |elem| from_serializable(item_class, elem) }
        else
          return data.map { |elem| from_serializable(Object, elem) }
        end
      end

      if klass == StatementSeq
        return IrSerTxt.deserialize_statement_seq(data)
      end

      if klass.respond_to?(:from_h)
        transformed = data.transform_keys(&:to_sym).transform_values { |v| from_serializable(Object, v) }
        klass.from_h(transformed)
      else
        data
      end
    end

    def write_arch(arch, filepath)
      data = to_serializable(arch)
      File.write(filepath, YAML.dump(data))
    end

    def read_arch(filepath)
      data = YAML.load_file(filepath)
      from_serializable(Arch, data)
    end
  end
end
