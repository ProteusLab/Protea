# lira/classify.rb
# Derives per-instruction classification from a Lira::Instruction's semantic IR
# (see sim_gen_lira/ISA/isa.rb for the same idiom). Lives here, next to the LIRA
# arch model, so any lira.yaml consumer can reuse it and so lira_gen could later
# call it to bake attributes. Everything is *deduced* from the semantic — the
# only fact read back (never derived) is the extension, which the lowering
# preserves in `insn.attributes` as an { "ext" => <feature> } mapping.

module Lira
  module Classify
    module_function

    # Ordered list of flag symbols; the bit index of each flag is its position
    # here. Append-only: existing bit indices stay stable.
    FLAGS = %i[
      is_branch
      is_conditional_branch
      is_unconditional_branch
      may_load
      may_store
      is_terminator
      is_syscall
      is_call_like
      is_alu
      reads_pc
      writes_pc
    ].freeze

    # Per-operand role; index is the C++ Role enum value (imm = 0).
    ROLES = %i[imm src dst].freeze

    # A fully derived instruction description.
    Desc = Struct.new(:flags, :mem_width, :roles, :ext, keyword_init: true)

    def set_pc_stmt?(stmt)
      (stmt.kind == 'env' || stmt.kind == 'cond_env') && stmt.specifier == 'setPC'
    end

    def syscall_stmt?(stmt)
      (stmt.kind == 'env' || stmt.kind == 'cond_env') && stmt.specifier == 'sysCall'
    end

    # Conditional when the setPC target is produced by a select op (beq etc.),
    # or the statement itself is a cond_env. jal/jalr feed setPC from plain
    # arithmetic, so they classify as unconditional.
    def conditional_set_pc?(stmt, seq)
      return true if stmt.kind == 'cond_env'
      producer = begin
        stmt.input(0, seq)
      rescue StandardError
        # Target temp not found in the sequence (unreachable with current IR);
        # fall back to unconditional rather than failing the build.
        nil
      end
      !producer.nil? && producer.kind == 'op' && producer.specifier.start_with?('select')
    end

    # Full description for an instruction. Instructions with an empty semantic
    # (ebreak, fence) get no flags and all-imm roles.
    def describe(insn)
      seq = insn.semantic
      ext = ext_of(insn)
      operand_count = insn.operand_names.size
      return Desc.new(flags: [], mem_width: 0, roles: default_roles(operand_count), ext: ext) \
        unless seq && seq.stmts && !seq.stmts.empty?

      Desc.new(
        flags: flags_for(seq),
        mem_width: mem_width_for(seq),
        roles: roles_for(operand_count, seq),
        ext: ext
      )
    end

    # Returns the set of flag symbols for a (non-empty) semantic sequence.
    def flags_for(seq)
      stmts = seq.stmts
      set_pc_stmts = stmts.select { |s| set_pc_stmt?(s) }
      syscall = stmts.any? { |s| syscall_stmt?(s) }
      reads_pc = stmts.any? { |s| s.kind == 'env' && s.specifier == 'getPC' }
      may_load = stmts.any? { |s| s.kind == 'env' && s.specifier.start_with?('readMem') }
      may_store = stmts.any? { |s| s.kind == 'env' && s.specifier.start_with?('writeMem') }
      has_reg_write = stmts.any? { |s| s.kind == 'write' }

      flags = []
      unless set_pc_stmts.empty?
        flags << :is_branch
        # If an instruction somehow had both kinds of setPC, conditional wins.
        if set_pc_stmts.any? { |s| conditional_set_pc?(s, seq) }
          flags << :is_conditional_branch
        else
          flags << :is_unconditional_branch
          # Unconditional jump that also writes a register (the link register):
          # jal/jalr. Opcode-static, so `jal x0` still reports call-like.
          flags << :is_call_like if has_reg_write
        end
      end
      flags << :may_load if may_load
      flags << :may_store if may_store
      flags << :is_terminator if !set_pc_stmts.empty? || syscall
      flags << :is_syscall if syscall
      # Computational: writes a register with no memory access or control transfer.
      flags << :is_alu if has_reg_write && !may_load && !may_store && set_pc_stmts.empty?
      flags << :reads_pc if reads_pc
      flags << :writes_pc unless set_pc_stmts.empty?
      flags
    end

    # Memory access width in bytes, from the readMem<N>/writeMem<N> env
    # specifier (e.g. readMem32 -> 4). 0 if not a memory op.
    def mem_width_for(seq)
      seq.stmts.each do |s|
        next unless s.kind == 'env'
        m = s.specifier.match(/\A(?:read|write)Mem(\d+)\z/)
        return m[1].to_i / 8 if m
      end
      0
    end

    # Per-operand role, in operand_names order: a register read of an operand
    # -> :src, a register write -> :dst, everything else -> :imm. The register
    # number is inputs[0] of a read/write statement, produced by an `input N`.
    def roles_for(operand_count, seq)
      roles = default_roles(operand_count)
      prod = producers(seq)
      seq.stmts.each do |s|
        next unless (s.kind == 'read' || s.kind == 'write') && !s.inputs.empty?
        idx = operand_index(s.inputs[0], prod)
        next unless idx && idx >= 0 && idx < roles.size
        roles[idx] = s.kind == 'read' ? :src : :dst
      end
      roles
    end

    def default_roles(operand_count)
      Array.new(operand_count, :imm)
    end

    # Map each SSA temp to the statement that produces it.
    def producers(seq)
      map = {}
      seq.stmts.each { |s| s.outputs.each { |o| map[o] = s } }
      map
    end

    # If `temp` is produced directly by an `input N`, return N, else nil.
    def operand_index(temp, prod)
      st = prod[temp]
      return nil unless st && st.kind == 'input'
      st.specifier.to_i
    end

    # Extension preserved by the lowering in `attributes` as an { "ext" =>
    # <feature> } mapping.
    def ext_of(insn)
      attr = (insn.attributes || []).find { |a| a.is_a?(Hash) && a.key?('ext') }
      attr ? attr['ext'].to_s : ''
    end
  end
end
