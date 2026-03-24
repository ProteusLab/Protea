require 'Utility/type'

# frozen_string_literal: true
# Utility methods simulator's code generation
module Utility
  # Utility methods simulator's code generation in C++
  module HelperCpp
    module_function

    def gen_type(type)
      actual_type = Utility.get_type(type)
      cpp_bitsize = actual_type.bitsize % 32 == 0 ? actual_type.bitsize : (actual_type.bitsize / 32 + 1) * 32
      "#{actual_type.typeof == :s ? 'int' : 'uint'}#{cpp_bitsize}_t"
    end

    def gen_small_type(type)
      actual_type = Utility.get_type(type)
      cpp_bitsize = [8, 1 << (actual_type.bitsize - 1).bit_length].max
      "#{actual_type.typeof == :s ? 'int' : 'uint'}#{cpp_bitsize}_t"
    end
  end
end
