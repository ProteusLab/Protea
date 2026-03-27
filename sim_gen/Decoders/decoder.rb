require 'Utility/gen_emitter'
require 'Utility/helper_cpp'
require 'code_gen/cpp_gen'

module SimGen
    module Decoder
        module Helper
            module_function

            def calc_insn_mask(insn)
                mask = 0
                for field in insn[:fields]
                    if !field[:value][:value_num].nil?
                        field_mask = ((1 << (field[:from] - field[:to] + 1)) - 1) << field[:to]
                        mask |= field_mask
                    end
                end
                mask
            end

            def calc_insn_value(insn)
                value = 0
                for field in insn[:fields]
                    if !field[:value][:value_num].nil?
                        field_value = field[:value][:value_num] << field[:to]
                        value |= field_value
                    end
                end
                value
            end

            def get_maj_range(lead_bits)
                bits = lead_bits.keys.sort
                best_range = [bits[0], bits[0]]
                best_count = 0

                for i in 0...bits.size
                    score = 0
                    lsb = bits[i]
                    for j in i...bits.size
                        bit = bits[j]
                        if bit != lsb + (j - i)
                            break
                        end

                        score += lead_bits[bit].min
                        if score > best_count
                            best_count = score
                            best_range = [lsb, bit]
                        end
                    end
                end
                best_range
            end
            
            def get_lead_bits(instructions, separ_mask = 0)
                lead_bits = {}
                max_len = instructions.map { |insn| insn[:XLEN] * 8 }.max
            
                for bit in 0...max_len
                    next if (separ_mask & (1 << bit)) != 0
            
                    count_0 = 0
                    count_1 = 0
                    all_have_bit = true
            
                    for insn in instructions
                        insn_mask = calc_insn_mask(insn)
                        insn_value = calc_insn_value(insn)
            
                        if (insn_mask & (1 << bit)) == 0
                            all_have_bit = false
                            break
                        end
            
                        if (insn_value & (1 << bit)) != 0
                            count_1 += 1
                        else
                            count_0 += 1
                        end
                    end
            
                    if all_have_bit && count_0 > 0 && count_1 > 0
                        lead_bits[bit] = [count_0, count_1]
                    end
                end
            
                lead_bits
            end

            def make_head_tree(instructions)
                lead_bits = get_lead_bits(instructions)
                lsb, msb = get_maj_range(lead_bits)
                width = msb - lsb + 1
                
                tree = {}
                tree[:range] = [lsb, msb]
                tree[:nodes] = {}

                for node_value in 0...(1 << width)
                    actual_node = node_value << lsb
                    subtree = {}

                    result, is_leaf = make_child_tree(actual_node, ((1 << width) - 1) << lsb, instructions, subtree)

                    if is_leaf
                        tree[:nodes][node_value] = result
                    elsif !subtree.empty?
                        tree[:nodes][node_value] = subtree
                    end
                end
                tree
            end

            def filter_instructions(instructions, node, separ_mask)
                res = []
                for insn in instructions
                    insn_mask = calc_insn_mask(insn)
                    insn_value = calc_insn_value(insn)
                    if (insn_mask & separ_mask) != separ_mask
                        next
                    end
                    if (insn_value & separ_mask) == (node & separ_mask)
                        res << insn
                    end
                end
                res
            end

            def make_child_tree(node_value, separ_mask, instructions, subtree)
                sublits = filter_instructions(instructions, node_value, separ_mask)
                if sublits.empty?
                    return nil, false
                end
                if sublits.size == 1
                    return sublits[0], true
                end
                lead_bits = get_lead_bits(sublits, separ_mask)
                lsb, msb = get_maj_range(lead_bits)
                width = msb - lsb + 1
                subtree[:range] = [lsb, msb]
                subtree[:nodes] = {}

                new_mask = separ_mask | ((1 << width) - 1) << lsb

                for child_value in 0...(1 << width)
                    actual_node = node_value | child_value << lsb
                    child_subtree = {}
                    result, is_leaf = make_child_tree(actual_node, new_mask, sublits, child_subtree)
                    if is_leaf
                        subtree[:nodes][child_value] = result
                    elsif !child_subtree.empty?
                        subtree[:nodes][child_value] = child_subtree
                    end
                end
                return subtree, false
            end

            def map_operands(insn)
                operands = {}
                cnt = 0
                for node in insn[:map][:tree]
                    if node[:name] == :new_var && !node[:attrs].nil? && node[:attrs].include?(:op)
                        operands[node[:oprnds][0][:name]] = "insn.operand#{cnt}"
                        cnt += 1
                    end
                end
                operands
            end

            def generate_mapping_fields(insn)
                emitter = Utility::GenEmitter.new
                for node in insn[:fields]
                    var_type = Utility::HelperCpp.gen_type(Utility.get_type(node[:value][:type]).bitsize)
                    emitter.emit_line("#{var_type} #{node[:value][:name]} = slice<#{node[:from]}, #{node[:to]}>(raw_insn);")
                end
                emitter
            end

            def emit_binary_op(emitter, operand_map, op, dest, src1, src2)
                var = operand_map[dest[:name]] || dest[:name]
                expr1 = operand_map[src1[:name]] || src1[:name]
                expr2 = operand_map[src2[:name]] || src2[:name]
                expr1 = expr1.nil? ? src1[:value] : expr1
                expr2 = expr2.nil? ? src2[:value] : expr2
                emitter.emit_line("#{var} = #{expr1} #{op} #{expr2};")
            end

            def generate_mapping_body(insn)
                emitter = Utility::GenEmitter.new
                operand_map = map_operands(insn)
                gen = CodeGen::CppGenerator.new(emitter, operand_map)
                for node in insn[:map][:tree]
                    gen.generate_statement(node)
                end
                emitter
            end

            def generate_decoder_impl(tree)
                emitter = Utility::GenEmitter.new
                emitter.emit_line("switch ((raw_insn >> #{tree[:range][0]}) & 0b#{((1 << (tree[:range][1] - tree[:range][0] + 1)) - 1).to_s(2)}) {")
                emitter.increase_indent
                for node_value, node in tree[:nodes].to_a
                    emitter.emit_line("case 0b#{node_value.to_s(2)}: {")
                    emitter.increase_indent
                    if node.key?(:name)
                        body_emitter = Helper.generate_mapping_body(node)

                        fields_emitter = Helper.generate_mapping_fields(node)
                        
                        body_emitter.increase_indent_all emitter.indent_size * emitter.indent_level
                        fields_emitter.increase_indent_all emitter.indent_size * emitter.indent_level

                        emitter.emit_line("// Decoded instruction: #{node[:name]}")
                        emitter.emit_line("insn.m_opc = Opcode::k#{node[:name].to_s.upcase};")
                        emitter.concat(fields_emitter)
                        emitter.concat(body_emitter)
                        emitter.emit_line("return insn;")
                    else
                        rec_emitter = generate_decoder_impl(node)
                        rec_emitter.increase_indent_all 2
                        emitter.concat(rec_emitter)
                    end
                    emitter.decrease_indent
                    emitter.emit_line("}")
                end
                emitter.decrease_indent
                emitter.emit_line("}")
                emitter
            end

        end

        module Header
            module_function
            def generate_decoder(input_ir)
"#ifndef GENERATED_#{input_ir[:isa_name].upcase}_DECODER_HH_INCLUDED
#define GENERATED_#{input_ir[:isa_name].upcase}_DECODER_HH_INCLUDED

#include \"isa.hh\"
#include <optional>
#include <limits>
                
namespace prot::decoder {
using namespace prot::isa;
std::optional<Instruction> decode(const uint32_t raw_insn);
} // namespace generated::#{input_ir[:isa_name].downcase}::decoder

#endif // GENERATED_#{input_ir[:isa_name].upcase}_DECODER_HH_INCLUDED"            
            end
        end

        module TranslationUnit
            module_function
            def generate_decoder(input_ir)
                tree = Helper::make_head_tree(input_ir[:instructions])
                decoder_impl = Helper::generate_decoder_impl(tree)
                decoder_impl.increase_indent_all 2
"#include \"decoder.hh\"
#include <optional>

namespace {
consteval std::size_t toBits(std::size_t bytes) {
  return bytes * std::numeric_limits<unsigned char>::digits;
}

template <typename T> consteval std::size_t sizeofBits() {
  return toBits(sizeof(T));
}

template <typename T>
constexpr auto toUnderlying(T val)
  requires std::is_enum_v<T>
{
  return static_cast<std::underlying_type_t<T>>(val);
}

template <std::unsigned_integral T> consteval T ones(std::size_t Num) {
  if (Num > sizeofBits<T>()) {
    // OK, we're in constexpr context
    throw \"Num exceeds amount of bits\";
  }
  if (Num == sizeofBits<T>()) {
    return ~T{};
  }
  return (T{1} << Num) - std::uint32_t{1};
}

template <std::unsigned_integral T>
consteval T getMask(std::size_t Msb, std::size_t Lsb) {
  if (Msb < Lsb) {
    throw \"Illegal bits range\";
  }
  return ones<T>(Msb - Lsb + 1) << Lsb;
}

template <std::size_t Msb, std::size_t Lsb, std::unsigned_integral T>
constexpr T slice(T word) {
  static_assert(Msb >= Lsb, \"Error : illegal bits range\");
  static_assert(Msb <= sizeofBits<T>());
  return (word & getMask<T>(Msb, Lsb)) >> Lsb;
}
} // namespace

namespace prot::decoder {
using namespace isa;
std::optional<Instruction> decode(const isa::Word raw_insn) {
  Instruction insn{};
#{decoder_impl}
  return {}; // No matching instruction found
}
} // namespace generated::#{input_ir[:isa_name].downcase}::decoder
"
            end
        end
    end
end
