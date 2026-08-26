# frozen_string_literal: true

require_relative 'ir'
require_relative 'types'
require_relative 'diagnostics'

module Plod
  class Checker
    def self.check(program)
      new(program).check
    end

    def initialize(program)
      @program = program
      @diag = DiagnosticBag.new
      @components = program.components.to_h { |c| [c.name, c] }
      @objects = program.objects
      @functions = program.functions
    end

    attr_reader :diag, :components

    def check
      @program.components.each { |c| check_component(c) }
      @program.devices.each { |d| check_device(d) }
      @diag
    end

    private

    def error(msg, node)
      @diag.error(msg, node.respond_to?(:loc) ? node.loc : nil)
    end

    def warning(msg, node)
      @diag.warning(msg, node.respond_to?(:loc) ? node.loc : nil)
    end

    def check_component(component)
      check_duplicate_members(component)
      component.methods.each { |m| check_method(m, component, nil) unless m.abstract }
    end

    def check_duplicate_members(component)
      names = component.fields.map(&:name) + component.methods.map(&:name)
      names.tally.each do |name, count|
        error("duplicate member '#{name}' in #{component.abstract ? 'abstract struct' : 'struct'} #{component.name}", component) if count > 1
      end
    end

    def check_device(device)
      check_device_names(device)
      device.registers.each { |r| check_register(device, r) }
      check_register_overlaps(device)
      device.enums.each { |e| check_enum(e) }
      device.consts.each { |c| check_const(c) }
      device.methods.each { |m| check_method(m, nil, device) }
      device.lambdas.each { |l| check_method(l, nil, device) }
      check_ctor(device)
    end

    def check_device_names(device)
      names = {}
      device.registers.each { |r| register_name_clash(names, r.name, 'register', r) }
      device.fields.each { |f| register_name_clash(names, f.name, 'field', f) }
      device.consts.each { |c| register_name_clash(names, c.name, 'constant', c) }
      device.enums.each { |e| register_name_clash(names, e.name, 'enum', e) }
      device.methods.each { |m| register_name_clash(names, m.name, 'method', m) }
    end

    def register_name_clash(names, name, what, node)
      if names.key?(name)
        error("duplicate name '#{name}': #{what} clashes with #{names[name]}", node)
      else
        names[name] = what
      end
    end

    def check_register(device, reg)
      error("register #{reg.name}: size must be a positive integer, got #{reg.size.inspect}", reg) unless reg.size.is_a?(Integer) && reg.size.positive?
      error("register #{reg.name}: offset must be a non-negative integer, got #{reg.offset.inspect}", reg) unless reg.offset.is_a?(Integer) && reg.offset >= 0
      if reg.seqn && (!reg.seqn.is_a?(Integer) || reg.seqn < 1)
        error("register #{reg.name}: seqn must be a positive integer, got #{reg.seqn.inspect}", reg)
      end

      reg.fields.each { |f| check_reg_field(reg, f) }
      check_reg_field_overlaps(reg)

      read = reg.methods.find { |m| m.name == :read }
      write = reg.methods.find { |m| m.name == :write }
      if reg.access == :ro && write
        error("read-only register #{device.name}.#{reg.name} must not define a write method", write)
      end
      if reg.access == :wo && read
        error("write-only register #{device.name}.#{reg.name} must not define a read method", read)
      end

      reg_bits = Types::Bits.new(reg.size * 8)
      if read && read.ret_type && read.ret_type != reg_bits
        error("read method of #{reg.name} must return #{reg_bits.name}, got #{read.ret_type.name}", read)
      end
      if write
        data_arg = write.args.first
        if data_arg.nil? || data_arg[0] != :data || !data_arg[1].is_a?(Types::Bits) || !type_matches(data_arg[1], reg_bits)
          error("write method of #{reg.name} must take (data: #{reg_bits.name}) as its first argument", write)
        end
      end

      reg.methods.each { |m| check_method(m, nil, device, reg) }

      return if reg.enable_if.nil?

      ctx = TypeContext.new(self, reg_env(device, reg), nil)
      t = ctx.expr_type(reg.enable_if)
      unless t.nil? || t.boolean? || t.numeric?
        error("enableIf of #{reg.name} must be boolean or numeric, got #{t.name}", reg.enable_if)
      end
    end

    def check_reg_field(reg, field)
      total_bits = reg.size * 8
      unless field.lsb.is_a?(Integer) && field.lsb >= 0
        error("field #{reg.name}.#{field.name}: lsb must be a non-negative integer", field)
        return
      end
      return unless field.size.is_a?(Integer) && field.size >= 1

      return unless field.lsb + field.size > total_bits

      error("field #{reg.name}.#{field.name} [#{field.lsb}..#{field.lsb + field.size - 1}] exceeds register width of #{total_bits} bits", field)
    end

    def check_reg_field_overlaps(reg)
      sorted = reg.fields.sort_by(&:lsb)
      sorted.each_cons(2) do |a, b|
        next unless a.lsb + a.size > b.lsb

        error("fields #{reg.name}.#{a.name} and #{reg.name}.#{b.name} overlap", b)
      end
    end

    def check_register_overlaps(device)
      device.registers.each do |a|
        device.registers.each do |b|
          next if a.object_id >= b.object_id
          next if a.access == :ro && b.access == :wo || a.access == :wo && b.access == :ro
          next if a.enable_if || b.enable_if

          a_lo = a.offset
          a_hi = a.offset + a.size * (a.seqn || 1)
          b_lo = b.offset
          b_hi = b.offset + b.size * (b.seqn || 1)
          next unless a_lo < b_hi && b_lo < a_hi

          warning("registers #{a.name} [#{format('0x%x', a_lo)}..#{format('0x%x', a_hi)}) and " \
                  "#{b.name} [#{format('0x%x', b_lo)}..#{format('0x%x', b_hi)}) overlap; dispatch order decides", b)
        end
      end
    end

    def check_enum(enum_decl)
      error("enum #{enum_decl.name} has no values", enum_decl) if enum_decl.values.empty?
      enum_decl.values.each do |key, value|
        error("enum #{enum_decl.name}.#{key} must be an integer, got #{value.inspect}", enum_decl) unless value.is_a?(Integer)
      end
    end

    def check_const(const_decl)
      t = const_decl.type
      v = const_decl.value
      case v
      when Integer
        unless t.numeric? || t.is_a?(Types::Named)
          error("constant #{const_decl.name} of type #{t.name} cannot take integer value", const_decl)
        end
        if t.is_a?(Types::Bits) && v >= (1 << t.size)
          error("constant #{const_decl.name} value #{v} does not fit in #{t.name}", const_decl)
        end
      when String
        error("constant #{const_decl.name} of type #{t.name} cannot take a string value", const_decl) unless t.is_a?(Types::Str)
      when TrueClass, FalseClass
        error("constant #{const_decl.name} of type #{t.name} cannot take a boolean value", const_decl) unless t.boolean?
      end
    end

    def check_ctor(device)
      ctor = device.ctor
      return if ctor.nil?

      field_names = device.fields.map(&:name)
      ctor.inits.each do |init|
        unless field_names.include?(init.field)
          error("Init of unknown field '#{init.field}' of device #{device.name}", init)
          next
        end
        field = device.fields.find { |f| f.name == init.field }
        if field.abstract
          error("Init of abstract field '#{init.field}' is not allowed", init)
        end
      end
      inited = ctor.inits.map(&:field).tally
      inited.each do |name, count|
        error("field '#{name}' initialized twice in constructor of #{device.name}", ctor) if count > 1
      end
      ctor.body.each { |s| check_stmt(s, TypeContext.new(self, device_env(device), nil)) }
    end

    def check_method(method, component, device, register = nil)
      return if method.body.nil?

      scope = if register
                reg_env(device, register)
              elsif component
                component_env(component)
              else
                device_env(device)
              end
      method.args.each { |n, t| scope[n] = [:arg, t] }
      ctx = TypeContext.new(self, scope, method, device: device, register: register)
      method.body.each { |s| check_stmt(s, ctx) }
    end

    def component_env(component)
      env = {}
      component.fields.each { |f| env[f.name] = [:field, f.type] }
      component.methods.each { |m| env[m.name] = [:fn, m] }
      @objects.each { |n, t| env[n] = [:var, t] }
      @functions.each { |n, m| env[n] = [:fn, m] }
      env
    end

    def device_env(device)
      env = {}
      env[:__this__] = [:self, Types::Named.new(device.name)]
      device.registers.each { |r| env[r.name] = [:reg, r] }
      device.fields.each { |f| env[f.name] = [:field, f.type] }
      device.consts.each { |c| env[c.name] = [:const, c.type] }
      device.enums.each { |e| env[e.name] = [:enum, e] }
      device.methods.each { |m| env[m.name] = [:fn, m] }
      @objects.each { |n, t| env[n] = [:var, t] }
      @functions.each { |n, m| env[n] = [:fn, m] }
      env
    end

    def reg_env(device, reg)
      env = device_env(device)
      self_ref = Types::Bits.new(reg.size * 8)
      env[:__this__] = [:self, self_ref, :register]
      reg.fields.each { |f| env[f.name] = [:regfield, Types::Field.new(f.size), [reg, f]] }
      reg.methods.each { |m| env[m.name] = [:regfn, m] }
      env
    end

    def check_stmt(stmt, ctx)
      case stmt.kind
      when :vardecl
        ctx.define_local(stmt.name, stmt.type)
      when :assign
        target_t = ctx.expr_type(stmt.target)
        value_t = ctx.expr_type(stmt.value)
        check_assignable(stmt, stmt.target, target_t)
        check_compat(value_t, target_t, stmt.value, "assignment to #{describe(stmt.target)} of type #{target_t&.name || '?'}")
      when :exprstmt
        t = ctx.expr_type(stmt.expr)
        if t && !t.void? && stmt.expr.kind != :call && stmt.expr.kind != :mcall
          warning("value of type #{t.name} is discarded", stmt)
        end
      when :if
        cond_t = ctx.expr_type(stmt.cond)
        unless cond_t.nil? || cond_t.boolean? || cond_t.numeric?
          error("condition must be boolean or numeric, got #{cond_t.name}", stmt.cond)
        end
        ctx.scoped do
          stmt.then_body.each { |s| check_stmt(s, ctx) }
        end
        stmt.elsif_list.each do |cond, body|
          c_t = ctx.expr_type(cond)
          unless c_t.nil? || c_t.boolean? || c_t.numeric?
            error("else-if condition must be boolean or numeric, got #{c_t.name}", cond)
          end
          ctx.scoped do
            body.each { |s| check_stmt(s, ctx) }
          end
        end
        ctx.scoped do
          (stmt.else_body || []).each { |s| check_stmt(s, ctx) }
        end
      when :for
        ctx.expr_type(stmt.from)
        ctx.expr_type(stmt.to)
        ctx.scoped do
          ctx.define_local(stmt.iter, Types::Int.new)
          stmt.body.each { |s| check_stmt(s, ctx) }
        end
      when :return
        ctx.check_return(stmt)
      when :setelem
        container = stmt.container
        ct = ctx.expr_type(container)
        elem_t = elem_type(ct, container, ctx)
        idx_t = ctx.expr_type(stmt.index)
        unless idx_t.nil? || idx_t.numeric?
          error("index must be numeric, got #{idx_t.name}", stmt.index)
        end
        vt = ctx.expr_type(stmt.value)
        check_compat(vt, elem_t, stmt.value, "element assignment of type #{elem_t&.name || '?'}")
      when :initcall
        stmt.args.each { |a| ctx.expr_type(a) }
      else
        ctx.expr_type(stmt)
      end
    end

    def elem_type(container_type, container, ctx)
      t = container_type
      return t.elem if t.is_a?(Types::Array)

      binding = ctx.lookup(container.name) if container.kind == :var
      return Types::Bits.new(binding[2].size * 8) if binding && binding[0] == :reg && binding[2].seqn

      nil
    end

    def check_assignable(stmt, target, _type)
      case target.kind
      when :var, :regfield, :self, :getelem, :getfield
        nil
      else
        error("cannot assign to #{target.kind} expression", stmt)
      end
    end

    def describe(node)
      case node.kind
      when :var then "variable '#{node.name}'"
      when :regfield then "field '#{node.field}'"
      when :self then 'this'
      when :getelem then 'element'
      when :getfield then "field '#{node.name}'"
      else node.kind.to_s
      end
    end

    def check_compat(actual, expected, node, what)
      return if expected.nil? || actual.nil?

      if node.is_a?(Struct) && node.respond_to?(:kind) && node.kind == :const &&
         node.value.is_a?(Integer) && expected.is_a?(Types::Bits) &&
         (node.value.negative? || node.value >= (1 << expected.size))
        error("value #{node.value} does not fit in #{expected.name}", node)
        return
      end

      return if type_matches(actual, expected)

      error("#{what}, got #{actual.name}", node)
    end

    def type_matches(actual, expected)
      return true if actual == expected
      return true if actual.is_a?(Types::Named) && expected.is_a?(Types::Named)
      return true if actual.is_a?(Types::Ptr) && expected.is_a?(Types::Ptr)

      if actual.is_a?(Types::Bits) && expected.is_a?(Types::Bits)
        return actual.size <= expected.size
      end
      return true if actual.is_a?(Types::Int) && (expected.bits? || expected.boolean?)
      return true if expected.is_a?(Types::Int) && (actual.bits? || actual.boolean?)
      return true if actual.boolean? && (expected.bits? || expected.is_a?(Types::Int))
      return true if expected.boolean? && (actual.bits? || actual.is_a?(Types::Int))

      false
    end

    class TypeContext
      attr_reader :method_decl, :device

      def initialize(checker, env, method_decl, device: nil, register: nil)
        @checker = checker
        @env = env
        @locals = [{}]
        @method_decl = method_decl
        @device = device
        @register = register
      end

      def lookup(name)
        @locals.reverse_each do |scope|
          return scope[name] if scope.key?(name)
        end
        @env[name]
      end

      def define_local(name, type)
        @locals.last[name] = [:local, type]
      end

      def scoped
        @locals.push({})
        yield
        @locals.pop
      end

      def check_return(stmt)
        ret_t = @method_decl&.ret_type
        if stmt.value.nil?
          error("method #{@method_decl.name} returns #{@method_decl.ret_type ? @method_decl.ret_type.name : 'void'} but return has no value", stmt) if ret_t
          return
        end
        value_t = expr_type(stmt.value)
        if ret_t.nil?
          error("void method #{@method_decl.name} cannot return a value", stmt)
        else
          @checker.send(:check_compat, value_t, ret_t, stmt.value, "return type of #{@method_decl.name} is #{ret_t.name}")
        end
      end

      def expr_type(node)
        return nil if node.nil?

        case node.kind
        when :var
          binding = lookup(node.name)
          if binding.nil?
            error("unknown name '#{node.name}'", node)
            return nil
          end
          case binding[0]
          when :reg
            reg = binding[1]
            reg.seqn ? Types::Array.new(Types::Bits.new(reg.size * 8), reg.seqn) : Types::Bits.new(reg.size * 8)
          when :enum
            error("enum '#{node.name}' used as a value", node)
            nil
          when :fn, :regfn
            error("method '#{node.name}' must be called", node)
            nil
          else
            binding[1]
          end
        when :const
          node.value.is_a?(String) ? Types::Str.new : Types::Int.new
        when :self
          binding = lookup(:__this__)
          binding ? binding[1] : nil
        when :binop
          binop_type(node)
        when :unop
          t = expr_type(node.operand)
          if t && !t.bits?
            error("'~' requires a bit value, got #{t.name}", node)
            nil
          else
            t
          end
        when :cast
          expr_type(node.value)
          node.type
        when :regfield
          reg_node = node.reg
          reg_t = expr_type(reg_node)
          field = find_field(reg_node, node.field)
          if field.nil?
            error("unknown register field '#{node.field}'", node)
            return nil
          end
          reg_bits = reg_bits_of(reg_node)
          if reg_bits && field.lsb + field.size > reg_bits.size
            error("field '#{node.field}' exceeds register width", node)
          end
          reg_t.nil? && reg_bits.nil? ? nil : Types::Field.new(field.size)
        when :getfield
          recv_t = expr_type(node.recv)
          return nil if recv_t.nil?

          target = recv_t.deref
          unless target.is_a?(Types::Named)
            error("cannot access field '#{node.name}' on non-struct type #{recv_t.name}", node)
            return nil
          end
          component = @checker.components[target.id]
          if component.nil?
            warning("late-bound field access '#{node.name}' on undeclared type '#{target.name}'", node)
            return nil
          end
          field = component.fields.find { |f| f.name == node.name }
          if field.nil?
            error("type #{target.name} has no field '#{node.name}'", node)
            return nil
          end
          field.type
        when :getelem
          ct = expr_type(node.container)
          idx_t = expr_type(node.index)
          unless idx_t.nil? || idx_t.numeric?
            error("index must be numeric, got #{idx_t.name}", node.index)
          end
          if ct.nil?
            nil
          elsif ct.is_a?(Types::Array)
            ct.elem
          else
            error("type #{ct.name} is not indexable", node)
            nil
          end
        when :enumval
          binding = lookup(node.enum)
          if binding.nil? || binding[0] != :enum
            error("unknown enum '#{node.enum}'", node)
            return nil
          end
          unless binding[1].values.key?(node.key)
            error("unknown enum value '#{node.enum}.#{node.key}'", node)
            return nil
          end
          Types::Int.new
        when :getptr
          expr_type(node.target)
          node.type
        when :mcall
          method_call_type(node)
        when :call
          call_type(node)
        else
          nil
        end
      end

      private

      def error(msg, node)
        @checker.diag.error(msg, node.respond_to?(:loc) ? node.loc : nil)
      end

      def warning(msg, node)
        @checker.diag.warning(msg, node.respond_to?(:loc) ? node.loc : nil)
      end

      def binop_type(node)
        lt = expr_type(node.lhs)
        rt = expr_type(node.rhs)
        return nil if lt.nil? && rt.nil?

        if %i[eq ne lt le gt ge].include?(node.op)
          if lt && rt && !operand_pair_ok?(lt, rt)
            error("cannot compare #{lt.name} with #{rt.name}", node)
            return nil
          end
          return Types::Bool.new
        end

        return nil if lt.nil? || rt.nil?

        unless numeric_like?(lt)
          error("operator '#{node.op}' requires numeric or string operands, got #{lt.name}", node)
          return nil
        end
        unless numeric_like?(rt)
          error("operator '#{node.op}' requires numeric or string operands, got #{rt.name}", node)
          return nil
        end
        if (lt.is_a?(Types::Str) && !rt.is_a?(Types::Str)) || (!lt.is_a?(Types::Str) && rt.is_a?(Types::Str))
          error("cannot mix string and numeric operands in '#{node.op}'", node)
          return nil
        end

        node.type
      end

      def numeric_like?(t)
        t.numeric? || t.is_a?(Types::Str) || t.named?
      end

      def operand_pair_ok?(lt, rt)
        (lt.numeric? && rt.numeric?) || (lt.is_a?(Types::Str) && rt.is_a?(Types::Str)) || lt.is_a?(Types::Named) || rt.is_a?(Types::Named)
      end

      def find_field(reg_node, field_name)
        if reg_node.kind == :self
          @register&.fields&.find { |f| f.name == field_name }
        elsif reg_node.kind == :var
          binding = lookup(reg_node.name)
          binding && binding[0] == :reg ? binding[1].fields.find { |f| f.name == field_name } : nil
        end
      end

      def reg_bits_of(reg_node)
        if reg_node.kind == :self
          @register ? Types::Bits.new(@register.size * 8) : nil
        elsif reg_node.kind == :var
          binding = lookup(reg_node.name)
          binding && binding[0] == :reg ? Types::Bits.new(binding[1].size * 8) : nil
        end
      end

      def method_call_type(node)
        recv_t = expr_type(node.recv)
        check_arg_types(node.args) { |a| expr_type(a) }

        return nil if recv_t.nil?

        target = recv_t.deref

        method_decl = nil
        reg = nil
        if node.recv.kind == :self && @register
          method_decl = @register.methods.find { |m| m.name == node.name }
          reg = @register
        elsif node.recv.kind == :var
          binding = lookup(node.recv.name)
          if binding && binding[0] == :reg
            reg = binding[1]
            method_decl = reg.methods.find { |m| m.name == node.name }
          end
        end
        if method_decl.nil? && target.is_a?(Types::Named)
          component = @checker.components[target.id]
          if component.nil?
            warning("late-bound call '#{node.name}' on undeclared type '#{target.name}'", node)
            return nil
          end
          method_decl = component.methods.find { |m| m.name == node.name }
          if method_decl.nil?
            if component.abstract
              warning("late-bound call '#{node.name}' on abstract type '#{target.name}'", node)
              return nil
            end
            error("struct #{target.name} has no method '#{node.name}'", node)
            return nil
          end
        end
        if method_decl.nil?
          error("unknown method '#{node.name}'", node)
          return nil
        end

        check_call(node, method_decl)
        method_decl.ret_type
      end

      def call_type(node)
        check_arg_types(node.args) { |a| expr_type(a) }

        binding = lookup(node.name)
        if binding.nil?
          error("unknown function '#{node.name}'", node)
          return nil
        end
        unless %i[fn regfn].include?(binding[0])
          error("'#{node.name}' is not callable", node)
          return nil
        end

        check_call(node, binding[1])
        binding[1].ret_type
      end

      def check_arg_types(args)
        args.each { |a| yield a }
      end

      def check_call(node, method_decl)
        expected = method_decl.args
        if node.args.size != expected.size
          error("wrong number of arguments for '#{method_decl.name}': expected #{expected.size}, got #{node.args.size}", node)
          return
        end
        node.args.each_with_index do |arg, i|
          actual = expr_type(arg)
          expected_type = expected[i][1]
          next if actual.nil? || expected_type.nil?

          next if @checker.send(:type_matches, actual, expected_type)

          error("argument #{expected[i][0]} of '#{method_decl.name}' expects #{expected_type.name}, got #{actual.name}", arg)
        end
      end
    end
  end
end
