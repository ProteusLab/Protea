# lira/arch.rb
require 'set'

module Lira
  class Component
    attr_accessor :name, :attributes

    def initialize(name, attributes = [])
      @name = name
      @attributes = attributes
    end

    def to_h
      { name: name, attributes: attributes }
    end

    def self.from_h(hash)
      new(hash[:name] || hash['name'], hash[:attributes] || hash['attributes'] || [])
    end

    def ==(other)
      other.is_a?(Component) && name == other.name && attributes == other.attributes
    end
  end

  class Snippet
    attr_accessor :name, :seq

    def initialize(name, seq)
      @name = name
      @seq = seq
    end

    def to_h
      { name: name, seq: seq }
    end

    def self.from_h(hash)
      seq = StatementSeq.from_h(hash[:seq] || hash['seq'])
      new(hash[:name] || hash['name'], seq)
    end

    def ==(other)
      other.is_a?(Snippet) && name == other.name && seq == other.seq
    end
  end

  class Operation < Component
    attr_accessor :inputs, :outputs, :semantic_base, :semantic_func, :semantic_func_128, :semantic_table

    def initialize(name, attributes, inputs, outputs,
                   semantic_base: nil, semantic_func: nil, semantic_func_128: nil, semantic_table: nil)
      super(name, attributes)
      @inputs = inputs
      @outputs = outputs
      @semantic_base = semantic_base
      @semantic_func = semantic_func
      @semantic_func_128 = semantic_func_128
      @semantic_table = semantic_table
    end

    def to_h
      super.merge(
        inputs: inputs,
        outputs: outputs,
        semantic_base: semantic_base,
        semantic_func: semantic_func,
        semantic_func_128: semantic_func_128,
        semantic_table: semantic_table
      )
    end

    def self.from_h(hash)
      name = hash[:name] || hash['name']
      attributes = hash[:attributes] || hash['attributes'] || []
      inputs = hash[:inputs] || hash['inputs']
      outputs = hash[:outputs] || hash['outputs']

      semantic_base = hash[:semantic_base] || hash['semantic_base']
      semantic_base = nil if semantic_base == {}
      semantic_func = hash[:semantic_func] || hash['semantic_func']
      semantic_func_128 = hash[:semantic_func_128] || hash['semantic_func_128']
      semantic_func_128 = nil if semantic_func_128 == {}
      semantic_table = hash[:semantic_table] || hash['semantic_table']
      semantic_table = nil if semantic_table == {}

      new(name, attributes, inputs, outputs,
          semantic_base: semantic_base,
          semantic_func: semantic_func,
          semantic_func_128: semantic_func_128,
          semantic_table: semantic_table)
    end

    def ==(other)
      super(other) &&
        other.is_a?(Operation) &&
        inputs == other.inputs &&
        outputs == other.outputs &&
        semantic_base == other.semantic_base &&
        semantic_func == other.semantic_func &&
        semantic_func_128 == other.semantic_func_128 &&
        semantic_table == other.semantic_table
    end
  end

  class Register < Component
    def initialize(name, attributes = [])
      super(name, attributes)
    end

    def to_h
      super.merge()
    end

    def self.from_h(hash)
      name = hash[:name] || hash['name']
      attributes = hash[:attributes] || hash['attributes'] || []
      new(name, attributes)
    end

    def ==(other)
      super(other) && other.is_a?(Register)
    end
  end

  class RegisterFile < Component
    attr_accessor :reg_size, :regs

    def initialize(name, attributes, reg_size, regs)
      super(name, attributes)
      @reg_size = reg_size
      @regs = regs
    end

    def reg_names
      @regs.map(&:name)
    end

    def regs_num
      @regs.length
    end

    def to_h
      super.merge(reg_size: reg_size.to_h, regs: regs.map(&:to_h))
    end

    def self.from_h(hash)
      name = hash[:name] || hash['name']
      attributes = hash[:attributes] || hash['attributes'] || []
      reg_size = Shape.from_h(hash[:reg_size] || hash['reg_size'])
      regs_data = hash[:regs] || hash['regs'] || []
      regs = regs_data.map { |r| Register.from_h(r) }
      new(name, attributes, reg_size, regs)
    end

    def ==(other)
      super(other) &&
        other.is_a?(RegisterFile) &&
        reg_size == other.reg_size &&
        regs == other.regs
    end
  end


  class EnvironmentFunction < Component
    attr_accessor :inputs, :outputs

    def initialize(name, attributes, inputs, outputs)
      super(name, attributes)
      @inputs = inputs
      @outputs = outputs
    end

    def to_h
      super.merge(inputs: inputs, outputs: outputs)
    end

    def self.from_h(hash)
      name = hash[:name] || hash['name']
      attributes = hash[:attributes] || hash['attributes'] || []
      inputs = hash[:inputs] || hash['inputs']
      outputs = hash[:outputs] || hash['outputs']
      new(name, attributes, inputs, outputs)
    end

    def ==(other)
      super(other) &&
        other.is_a?(EnvironmentFunction) &&
        inputs == other.inputs &&
        outputs == other.outputs
    end
  end

  class SystemRegisterField < Component
    attr_accessor :lsb, :msb

    def initialize(name, attributes, lsb, msb)
      super(name, attributes)
      @lsb = lsb
      @msb = msb
    end

    def to_h
      super.merge(lsb: lsb, msb: msb)
    end

    def self.from_h(hash)
      name = hash[:name] || hash['name']
      attributes = hash[:attributes] || hash['attributes'] || []
      lsb = hash[:lsb] || hash['lsb']
      msb = hash[:msb] || hash['msb']
      new(name, attributes, lsb, msb)
    end

    def ==(other)
      super(other) &&
        other.is_a?(SystemRegisterField) &&
        lsb == other.lsb &&
        msb == other.msb
    end
  end

  class SystemRegister < Component
    attr_accessor :size, :fields

    def initialize(name, attributes, size, fields)
      super(name, attributes)
      @size = size
      @fields = fields
    end

    def to_h
      super.merge(size: size, fields: fields.map(&:to_h))
    end

    def self.from_h(hash)
      name = hash[:name] || hash['name']
      attributes = hash[:attributes] || hash['attributes'] || []
      size = hash[:size] || hash['size']
      fields_data = hash[:fields] || hash['fields']
      fields = fields_data.map { |f| SystemRegisterField.from_h(f) }
      new(name, attributes, size, fields)
    end

    def ==(other)
      super(other) &&
        other.is_a?(SystemRegister) &&
        size == other.size &&
        fields == other.fields
    end
  end

  class TableInt < Component
    attr_accessor :values

    def initialize(name, attributes, values)
      super(name, attributes)
      @values = values
    end

    def to_h
      super.merge(values: values)
    end

    def self.from_h(hash)
      name = hash[:name] || hash['name']
      attributes = hash[:attributes] || hash['attributes'] || []
      values = hash[:values] || hash['values']
      new(name, attributes, values)
    end

    def ==(other)
      super(other) &&
        other.is_a?(TableInt) &&
        values == other.values
    end
  end

  class InstructionEncoding
    attr_accessor :encoded_size, :const_encoding_part, :const_mask, :decode, :encode,
                  :constraint_decode, :constraint_encode

    def initialize(encoded_size, const_encoding_part, const_mask, decode, encode, constraint_decode, constraint_encode)
      @encoded_size = encoded_size
      @const_encoding_part = const_encoding_part
      @const_mask = const_mask
      @decode = decode
      @encode = encode
      @constraint_decode = constraint_decode
      @constraint_encode = constraint_encode
    end

    def to_h
      {
        encoded_size: encoded_size,
        const_encoding_part: const_encoding_part,
        const_mask: const_mask,
        decode: decode,
        encode: encode,
        constraint_decode: constraint_decode,
        constraint_encode: constraint_encode
      }
    end

    def self.from_h(hash)
      new(hash[:encoded_size] || hash['encoded_size'],
          hash[:const_encoding_part] || hash['const_encoding_part'],
          hash[:const_mask] || hash['const_mask'],
          hash[:decode] || hash['decode'],
          hash[:encode] || hash['encode'],
          hash[:constraint_decode] || hash['constraint_decode'],
          hash[:constraint_encode] || hash['constraint_encode'])
    end

    def ==(other)
      other.is_a?(InstructionEncoding) &&
        encoded_size == other.encoded_size &&
        const_mask == other.const_mask &&
        const_encoding_part == other.const_encoding_part &&
        decode == other.decode &&
        encode == other.encode &&
        constraint_decode == other.constraint_decode &&
        constraint_encode == other.constraint_encode
    end
  end

  class Instruction < Component
    attr_accessor :operand_sizes, :operand_names, :encoding, :semantic

    def initialize(name, attributes, operand_sizes, operand_names, encoding, semantic)
      super(name, attributes)
      @operand_sizes = operand_sizes
      @operand_names = operand_names
      @encoding = encoding
      @semantic = semantic
    end

    def to_h
      super.merge(
        operand_sizes: operand_sizes,
        operand_names: operand_names,
        encoding: encoding.to_h,
        semantic: semantic
      )
    end

    def self.from_h(hash)
      name = hash[:name] || hash['name']
      attributes = hash[:attributes] || hash['attributes'] || []
      operand_sizes = hash[:operand_sizes] || hash['operand_sizes']
      operand_names = hash[:operand_names] || hash['operand_names']
      encoding = InstructionEncoding.from_h(hash[:encoding] || hash['encoding'])
      semantic = StatementSeq.from_h(hash[:semantic] || hash['semantic'])
      new(name, attributes, operand_sizes, operand_names, encoding, semantic)
    end

    def ==(other)
      super(other) &&
        other.is_a?(Instruction) &&
        operand_sizes == other.operand_sizes &&
        operand_names == other.operand_names &&
        encoding == other.encoding &&
        semantic == other.semantic
    end
  end

  class Arch < Component
    attr_accessor :register_files, :system_registers, :environment_functions,
                  :tables_int, :operations, :snippets, :instructions

    def initialize(name, attributes,
                   register_files: [],
                   system_registers: [],
                   environment_functions: [],
                   tables_int: [],
                   operations: [],
                   snippets: [],
                   instructions: [])
      super(name, attributes)
      @register_files = register_files
      @system_registers = system_registers
      @environment_functions = environment_functions
      @tables_int = tables_int
      @operations = operations
      @snippets = snippets
      @instructions = instructions
    end


    def to_h
      super.merge(
        register_files: register_files.map(&:to_h),
        system_registers: system_registers.map(&:to_h),
        environment_functions: environment_functions.map(&:to_h),
        tables_int: tables_int.map(&:to_h),
        operations: operations.map(&:to_h),
        snippets: snippets.map(&:to_h),
        instructions: instructions.map(&:to_h)
      )
    end

    def self.from_h(hash)
      name = hash[:name] || hash['name']
      attributes = hash[:attributes] || hash['attributes'] || []
      register_files = (hash[:register_files] || hash['register_files']).map { |rf| RegisterFile.from_h(rf) }
      system_registers = (hash[:system_registers] || hash['system_registers']).map { |sr| SystemRegister.from_h(sr) }
      environment_functions = (hash[:environment_functions] || hash['environment_functions']).map { |ef| EnvironmentFunction.from_h(ef) }
      tables_int = (hash[:tables_int] || hash['tables_int']).map { |ti| TableInt.from_h(ti) }
      operations = (hash[:operations] || hash['operations']).map { |op| Operation.from_h(op) }
      snippets = (hash[:snippets] || hash['snippets']).map { |sn| Snippet.from_h(sn) }
      instructions = (hash[:instructions] || hash['instructions']).map { |ins| Instruction.from_h(ins) }
      new(name, attributes,
          register_files: register_files,
          system_registers: system_registers,
          environment_functions: environment_functions,
          tables_int: tables_int,
          operations: operations,
          snippets: snippets,
          instructions: instructions)
    end

    def ==(other)
      super(other) &&
        other.is_a?(Arch) &&
        register_files == other.register_files &&
        system_registers == other.system_registers &&
        environment_functions == other.environment_functions &&
        tables_int == other.tables_int &&
        operations == other.operations &&
        snippets == other.snippets &&
        instructions == other.instructions
    end
  end
end
