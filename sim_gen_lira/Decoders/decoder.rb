# Decoders/decoder.rb
require_relative '../cpp_gen'

module SimGen
  module Decoder
    module Header
      module_function

      def generate_decoder(arch)
        <<~CPP
          #ifndef GENERATED_#{arch.name.upcase}_DECODER_HH_INCLUDED
          #define GENERATED_#{arch.name.upcase}_DECODER_HH_INCLUDED

          #include "isa.hh"
          #include <optional>

          using namespace prot::isa;

          namespace prot::decoder {
            std::optional<Instruction> decode(const uint32_t raw_insn);
          }

          #endif
        CPP
      end
    end

    module TranslationUnit
      module_function

      def generate_decoder(arch)
        snippets = arch.snippets.to_h { |s| [s.name, s.seq] }
        tree = build_decode_tree(arch.instructions)
        body = emit_tree(tree, 0, snippets, arch.instructions)
        <<~CPP
          #include "decoder.hh"
          #include "snippets.h"
          #include <optional>

          namespace prot::decoder {
          std::optional<Instruction> decode(isa::Word raw_insn) {
            Instruction insn{};
            #{body}
            return std::nullopt;
          }
          }
        CPP
      end

      private

      module_function

      def build_decode_tree(instructions)
        # Find the best discriminating bit range
        mask_union = instructions.map(&:encoding).map(&:const_mask).reduce(0, :|)
        mask_inter = instructions.map(&:encoding).map(&:const_mask).reduce(mask_union, :&)

        # Prefer bits in the intersection (checked by all), then union
        work_mask = mask_inter != 0 ? mask_inter : mask_union

        build_tree_node(instructions, work_mask, 0, 31)
      end

      def build_tree_node(instructions, work_mask, min_bit, max_bit)
        return nil if instructions.empty?
        return { leaf: instructions[0] } if instructions.size == 1

        # Find best discriminating bit range in work_mask
        lsb, msb = find_best_range(instructions, work_mask, min_bit, max_bit)
        return fallback_linear(instructions) unless lsb

        width = msb - lsb + 1
        mask = ((1 << width) - 1) << lsb

        # Group instructions by their value in this bit range
        groups = instructions.group_by { |insn| (insn.encoding.const_encoding_part & mask) >> lsb }

        node = { range: [lsb, msb], children: {} }
        groups.each do |val, group|
          next_mask = work_mask & ~mask
          if group.size == 1
            node[:children][val] = { leaf: group[0] }
          else
            child = build_tree_node(group, next_mask, min_bit, max_bit)
            node[:children][val] = child || { leaf: group[0] }
          end
        end
        node
      end

      def find_best_range(instructions, work_mask, min_bit, max_bit)
        lead_bits = {}
        (min_bit..max_bit).each do |bit|
          next if (work_mask & (1 << bit)) == 0
          count_0 = 0
          count_1 = 0
          all_have = true
          instructions.each do |insn|
            if (insn.encoding.const_mask & (1 << bit)) == 0
              all_have = false
              break
            end
            if (insn.encoding.const_encoding_part & (1 << bit)) != 0
              count_1 += 1
            else
              count_0 += 1
            end
          end
          lead_bits[bit] = [count_0, count_1] if all_have && count_0 > 0 && count_1 > 0
        end

        bits = lead_bits.keys.sort
        return nil if bits.empty?

        best_range = [bits[0], bits[0]]
        best_score = 0
        (0...bits.size).each do |i|
          score = 0
          (i...bits.size).each do |j|
            break if bits[j] != bits[i] + (j - i)
            score += lead_bits[bits[j]].min
            if score > best_score
              best_score = score
              best_range = [bits[i], bits[j]]
            end
          end
        end
        best_range
      end

      def fallback_linear(instructions)
        { linear: instructions }
      end

      def emit_tree(node, indent, snippets, all_instructions)
        if node[:leaf]
          insn = node[:leaf]
          emit_insn_block(insn, indent, snippets)
        elsif node[:linear]
          node[:linear].map { |insn| emit_insn_block(insn, indent, snippets) }.join("\n")
        else
          lsb, msb = node[:range]
          width = msb - lsb + 1
          mask = ((1 << width) - 1)
          shift = lsb

          lines = []
          ind = '  ' * indent
          lines << "#{ind}switch ((raw_insn >> #{shift}) & #{mask}) {"
          node[:children].sort.each do |val, child|
            lines << "#{ind}  case #{val}: {"
            lines << emit_tree(child, indent + 2, snippets, all_instructions)
            lines << "#{ind}  }"
          end
          lines << "#{ind}  default: break;"
          lines << "#{ind}}"
          lines.join("\n")
        end
      end

      def emit_insn_block(insn, indent, snippets)
        constraint_name = insn.encoding.constraint_decode
        decode_names = insn.encoding.decode
        return '' unless constraint_name && decode_names

        ind = '  ' * indent
        operand_calls = decode_names.each_with_index.map { |name, idx|
          "insn.operand#{idx} = #{name}(raw_insn);"
        }.join("\n#{ind}  ")

        <<~CPP
          #{ind}if (#{constraint_name}(raw_insn)) {
          #{ind}  #{operand_calls}
          #{ind}  insn.m_opc = Opcode::k#{insn.name.to_s.upcase};
          #{ind}  return insn;
          #{ind}}
        CPP
      end
    end
  end
end
