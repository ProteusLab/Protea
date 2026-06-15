require 'Utility/type'

# frozen_string_literal: true
# Utility methods simulator's code generation
module Utility
  # Utility methods simulator's code generation in C++
  module HelperCpp
    module_function

    def gen_type(type, signed = false)
      actual_type = Utility.get_type(type)
      width = actual_type.bitsize
      prefix = signed || actual_type.typeof == :s ? "" : "u"
      rounded = [1, 8, 16, 32, 64, 128].find { |s| s >= width } || 128
      rounded == 1 ? "bool" : "#{prefix}int#{rounded}_t"
    end

    def gen_small_type(type)
      actual_type = Utility.get_type(type)
      cpp_bitsize = [8, 1 << (actual_type.bitsize - 1).bit_length].max
      "#{actual_type.typeof == :s ? 'int' : 'uint'}#{cpp_bitsize}_t"
    end
  end
end
