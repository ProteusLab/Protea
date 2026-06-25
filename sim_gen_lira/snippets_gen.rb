require_relative 'cpp_gen'

module SimGen
  module Snippets
    module_function

    def generate_snippets_header(snippets)
      funcs = snippets
        .select { |s| s.name.start_with?('decode_') || s.name.start_with?('constraint_') }
        .map { |snip| generate_function(snip.name, snip.seq) }

      <<~CPP
        #ifndef GENERATED_SNIPPETS_H
        #define GENERATED_SNIPPETS_H

        #include <stdint.h>
        #include "base_ops.h"

        #{funcs.join("\n\n")}

        #endif
      CPP
    end

    def generate_function(name, seq)
      translator = LiraCppGen::Translator.new(seq, :snippet, 2)
      body = translator.translate
      <<~CPP
        static inline uint32_t #{name}(uint32_t raw_insn) {
        #{body}
        }
      CPP
    end
  end
end
