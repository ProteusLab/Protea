# lira/arch_utils.rb
require_relative 'arch'

module Lira
  ArchIndex = Struct.new(:rf, :sr, :env, :tables, :op, :snippet, :instr)

  def self.build_arch_index(arch)
    ArchIndex.new(
      arch.register_files.to_h { |rf| [rf.name, rf] },
      arch.system_registers.to_h { |sr| [sr.name, sr] },
      arch.environment_functions.to_h { |ef| [ef.name, ef] },
      arch.tables_int.to_h { |ti| [ti.name, ti] },
      arch.operations.to_h { |op| [op.name, op] },
      arch.snippets.to_h { |sn| [sn.name, sn] },
      arch.instructions.to_h { |ins| [ins.name, ins] }
    )
  end
end
