require 'code_gen/code_gen'
require 'Utility/gen_emitter'
require 'minitest/autorun'

class SemaTestsSimple < Minitest::Test
  def test_add_instruction
    operation = {
      name: 'add',
      oprnds: [
        { name: 'rd', type: 's32', regset: nil },
        { name: 'rs1', type: 's32', regset: nil },
        { name: 'rs2', type: 's32', regset: nil }
      ],
      attrs: nil
    }

    mapping = {
      'rd' => 'R[rd]',
      'rs1' => 'R[rs1]',
      'rs2' => 'R[rs2]'
    }

    expected_code = 'R[rd] = R[rs1] + R[rs2];'
    emitter = Utility::GenEmitter.new
    generated_code = CodeGen.new(emitter, mapping)
    generated_code.generate_statement(operation)

    assert_equal(expected_code, emitter.to_s)
  end

  def test_let_instruction
    operation = {
      name: 'let',
      oprnds: [
        { name: 'rd', type: 's32', regset: nil },
        { name: nil, type: 'iconst', value: 42 }
      ],
      attrs: nil
    }

    mapping = {
      'rd' => 'R[rd]'
    }

    expected_code = 'R[rd] = 42;'
    emitter = Utility::GenEmitter.new
    generated_code = CodeGen.new(emitter, mapping)
    generated_code.generate_statement(operation)

    assert_equal(expected_code, emitter.to_s)
  end

  def test_new_var_instruction
    operation = {
      name: 'new_var',
      oprnds: [
        { name: 'temp', type: 's32', regset: nil }
      ],
      attrs: nil
    }

    mapping = {}

    expected_code = 'int32_t temp;'
    emitter = Utility::GenEmitter.new
    generated_code = CodeGen.new(emitter, mapping)
    generated_code.generate_statement(operation)

    assert_equal(expected_code, emitter.to_s)
  end

  def test_cast_instruction
    operation = {
      name: 'cast',
      oprnds: [
        { name: 'rd', type: 's32', regset: nil },
        { name: 'rs', type: 'u16', regset: nil }
      ],
      attrs: nil
    }

    mapping = {
      'rd' => 'R[rd]',
      'rs' => 'R[rs]'
    }

    expected_code = 'R[rd] = (static_cast<int32_t>(R[rs]) << 16) >> 16;'
    emitter = Utility::GenEmitter.new
    generated_code = CodeGen.new(emitter, mapping)
    generated_code.generate_statement(operation)

    assert_equal(expected_code, emitter.to_s)
  end
end
