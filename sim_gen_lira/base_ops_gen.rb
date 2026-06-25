require 'stringio'
require_relative 'cpp_ops'

module SimGen
  def self.generate_base_ops(operations = [])
    out = StringIO.new
    generate_file(out, operations)
    out.string
  end

  class << self
    private

    HEADER = <<~'CPP'.freeze
#ifndef LIRA_STD_OPS_H
#define LIRA_STD_OPS_H

#include <stdint.h>

#ifdef __SIZEOF_INT128__
typedef unsigned __int128 uint128_t;
typedef __int128 int128_t;
#else
#error "128-bit integers not supported"
#endif
CPP

    FOOTER = "\n#endif\n"

    def generate_file(out, operations)
      out.puts HEADER
      operations.each { |op| out.puts op.to_cpp }
      out.puts
      out.puts FOOTER
    end
  end
end

if __FILE__ == $0
  output_file = ARGV[0] || 'std_ops.h'
  File.write(output_file, SimGen.generate_base_ops)
  puts "Generated #{output_file}"
end
