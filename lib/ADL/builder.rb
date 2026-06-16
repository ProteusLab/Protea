require_relative "scope"
require "Utility/type"

module SimInfra
    class IrStmt
        attr_reader :name, :oprnds, :attrs
        def initialize(name, oprnds, attrs)
            @name = name; @oprnds = oprnds; @attrs = attrs;
        end

        def to_h
            {
                name: @name,
                oprnds: @oprnds.map { |o|
                    if o.class == Var || o.class == Constant
                        o.to_h
                    else
                        o
                    end
                },
                attrs: @attrs,
            }
        end

        def self.from_h(h)
            IrStmt.new(h[:name], h[:oprnds], h[:attrs])
        end
    end
end

# Basics
module SimInfra
    def assert(condition, msg = nil); raise msg if !condition; end

    @@instructions = []
    @@interface_functions = []

    def self.interface_functions
        @@interface_functions
    end

    class InstructionInfo
        attr_accessor :name, :fields, :frmt, :map, :code, :map_code_blocks, :asm_str, :feature,
                      :operand_map, :operand_list
        def initialize(name, feature)
            @name = name;
            @map_code_blocks = {}
            @feature = feature
            @operand_map = {}
            @operand_list = []
        end

        def to_h
            {
                name: @name,
                fields: @fields.map { |f| f.to_h },
                frmt: @frmt,
                asm_str: @asm_str,
                code: @code.to_h,
                operand_map: @operand_map.transform_values(&:to_h),
                operand_list: @operand_list,
                feature: @feature,
            }
        end

        def self.from_h(h)
            info = InstructionInfo.new(h[:name], h[:feature])
            info.fields = h[:fields].map { |f| Field.from_h(f) }
            info.frmt = h[:frmt]
            info.asm_str = h[:asm_str]
            info.code = Scope.new(nil)
            info.code.instance_variable_set(:@tree, h[:code][:tree].map { |s| IrStmt.from_h(s) })
            if h[:operand_map]
                info.operand_map = h[:operand_map].transform_values { |v| Scope.from_h(v) }
                info.operand_list = h[:operand_list] || info.operand_map.keys
            end
            info
        end
    end

    class InstructionInfoBuilder
        include SimInfra

        def initialize(name, feature)
            @info = InstructionInfo.new(name, feature)
            @info.code = Scope.new(nil)

            @@interface_functions.each do |func|
                next if func[:kind] == :memory
                if !func[:return_types].empty?
                    @info.code.instance_eval "def #{func[:name]}(*args)
                        in_s = *args.map { |a| resolve_const(a) }
                        in_stmt = [tmpvar(#{func[:return_types][0]})]
                        in_stmt.concat(in_s)
                        return stmt :#{func[:name]}, in_stmt
                    end
                    "
                else
                    @info.code.instance_eval "def #{func[:name]}(*args)
                        in_s = *args.map { |a| resolve_const(a) }
                        return stmt :#{func[:name]}, in_s
                    end
                    "
                end
            end

            @info.map = Scope.new(nil)
        end

        def encoding(frmt, fields, *args)
            @info.fields = fields
            @info.frmt= frmt
            map args

            sum_bits = 0
            for f in fields
                sum_bits += Utility.get_type(f.value.type).bitsize
            end
        end
        attr_reader :info
    end

    def Instruction(name, &block)
        module_name = caller[0].split('\'')[1].split(':')[1][0..-2]

        bldr = InstructionInfoBuilder.new(name, module_name.to_sym)
        bldr.instance_eval &block
        @@instructions << bldr.info
        nil # only for debugging in IRB
    end

    class InterfaceBuilder
        include SimInfra

        def Function(name, output_types = [], input_types = [])
            @@interface_functions << {:name => name, :return_types => output_types, :argument_types => input_types}
        end
    end

    def Interface(&blck)
        bldr = InterfaceBuilder.new()
        bldr.instance_eval &blck
    end

    class RegisterFileInfo
        attr_accessor :name, :regs
        def initialize(name)
            @name = name; @regs = []
        end

        def to_h
            {
                name: @name,
                regs: @regs.map(&:to_h),
            }
        end

        def self.from_h(h)
            rf = new(h[:name])
            rf.regs = h[:regs].map { |r| Register.from_h(r) }
            rf
        end
    end

    class Register
        attr_reader :name, :size, :attrs
        def initialize(name, size, attrs)
            @name = name; @size = size; @attrs = attrs
        end

        def to_h
            {
                name: @name,
                size: @size,
                attrs: @attrs,
            }
        end

        def self.from_h(h)
            new(h[:name], h[:size], h[:attrs])
        end
    end

    @@regfiles = []
    class RegisterFileBuilder
      attr_reader :info

      def initialize(name)
        @info = RegisterFileInfo.new(name)
        @info.regs = []
      end

      def method_missing(name, *args)
        if name.to_s.start_with?('r')
          size = name.to_s[1..].to_i
          instance_eval "def #{name}(sym, *args); @info.regs << Register.new(sym, #{size}, args.size > 0 ? args : []); end", __FILE__, __LINE__
          @info.regs << Register.new(args[0], size, args.size > 1 ? args[1..] : [])
        else
          error "Unknown method #{name}"
        end
      end

      def zero = :zero
      def pc = :pc
    end

    def RegisterFile(name, &block)
        bldr = RegisterFileBuilder.new(name)
        bldr.instance_eval &block
        @@regfiles << bldr.info
        nil
    end

    def RegFiles()
        @@regfiles
    end
end

# * generate precise fields
module SimInfra
    class InstructionInfoBuilder
        def code(&block)
            # Link code scope methods to operand vars
            @info.operand_map.each do |name, scope|
                var = scope.vars[name]
                @info.code.method(name, var.type, var.regset) if var
            end

            # Register files
            for regfile in @@regfiles
                for reg in regfile.regs
                    @info.code.method(reg.name, ('r' + reg.size.to_s).to_sym)
                end
            end
            @info.code.instance_eval &block
        end

        def map(blocks)
            return if blocks.nil? || blocks.empty?
            blocks.each do |name, type, code_str|
                scope = Scope.new(nil)
                @info.fields.each { |f| scope.method(f.value.name, f.value.type) }
                scope.instance_eval(code_str)
                @info.operand_map[name] = scope
            end
            @info.operand_list = blocks.map(&:first)
        end

        def asm(&block)
            @info.asm_str = instance_eval &block
        end
    end
end
