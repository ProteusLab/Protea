require "Common/scope"
require "Utility/type"

# Basics
module Protea  
    def assert(condition, msg = nil); raise msg if !condition; end

    @@instructions = []
    @@interface_functions = []

    def self.interface_functions
        @@interface_functions
    end

    class InstructionInfo
        attr_accessor :name, :fields, :frmt, :map, :code, :map_code_blocks, :asm_str, :XLEN, :feature
        def initialize(name, feature)
            @name = name;
            @map_code_blocks = {}
            @feature = feature
        end

        def to_h
            {
                name: @name,
                fields: @fields.map { |f| f.to_h },
                frmt: @frmt,
                XLEN: @XLEN,
                asm_str: @asm_str,
                code: @code.to_h,
                map: @map.to_h,
                feature: @feature,
            }
        end

        def self.from_h(h)
            info = InstructionInfo.new(h[:name], h[:feature])
            info.fields = h[:fields].map { |f| Field.from_h(f) }
            info.frmt = h[:frmt]
            info.XLEN = h[:XLEN]
            info.asm_str = h[:asm_str]
            info.code = Scope.new(nil)
            info.code.instance_variable_set(:@tree, h[:code][:tree].map { |s| IrStmt.from_h(s) })
            info.map = Scope.new(nil)
            info.map.instance_variable_set(:@tree, h[:map][:tree].map { |s| IrStmt.from_h(s) })
            info
        end
    end

    class InstructionInfoBuilder
        include Protea

        def initialize(name, feature) 
            @info = InstructionInfo.new(name, feature) 
            @info.code = Scope.new(nil) 

            @@interface_functions.each do |func|
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
            @info.XLEN = sum_bits / 8
            @info.code.instance_eval "def xlen(); return #{@info.XLEN.to_s}; end"
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
        include Protea

        def function(name, output_types = [], input_types = [])
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
        def initialize(name) 
            @info = RegisterFileInfo.new(name)
            @info.regs = []
        end
        attr_reader :info
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
module Protea
    class RegisterFileBuilder
        def r32(sym, *args)
            @info.regs << Register.new(sym, 32, args[0] ? [args[0]] : [])
        end

        def zero()
            :zero
        end

        def pc()
            :pc
        end
    end

    class InstructionInfoBuilder
        def code(&block)
            if !@info.map_code_blocks.empty?
                @info.fields.each { |f|
                    @info.map.method(f.value.name, f.value.type)
                }
            end
            @info.map_code_blocks.each do |k, v|
                @info.map.instance_eval v[1]
            end
            @info.map_code_blocks.each do |k, v|
                @info.code.method(k, v[0], @info.map.vars[k].regset)
            end
            for regfile in @@regfiles
                for reg in regfile.regs
                    @info.code.method(reg.name, ('r' + reg.size.to_s).to_sym)
                end
            end
            @info.code.instance_eval &block
        end

        def map(blocks)
            if (!blocks.nil? && !blocks.empty?)
                for blck in blocks
                    @info.map_code_blocks[blck[0]] = [blck[1], blck[2]]
                end
            end
        end

        def asm(&block)
            @info.asm_str = instance_eval &block
        end
    end
end
