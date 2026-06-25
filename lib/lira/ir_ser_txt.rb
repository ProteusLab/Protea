# lira/ir_ser_txt.rb
require_relative 'ir'

def serialize_shape(shape)
  "#{shape.lanes_base}#{shape.lanes_mult}"
end

def deserialize_shape(s)
  m = s.match(/^(\d+)(.*)$/)
  Shape.new(m[1].to_i, m[2].empty? ? nil : m[2])
end

def serialize_statement(stmt)
  shape_str = serialize_shape(stmt.shape)
  out_parts = stmt.outputs_types.zip(stmt.outputs).flat_map { |typ, name| [typ.to_s, name] }
  parts = [shape_str] + out_parts + ['=', stmt.kind, stmt.specifier] + stmt.inputs
  parts.join(' ')
end

def deserialize_statement(s)
  m = s.match(/^(\w+)\s+(.*?)\s*=\s*(\w+)\s+(\S+)\s*(.*)$/)
  shape_str, outputs_str, kind, specifier, inputs_str = m.captures
  shape = deserialize_shape(shape_str)
  pairs = outputs_str.split
  outputs_types = (0...pairs.length).step(2).map { |i| pairs[i].to_i }
  outputs = (1...pairs.length).step(2).map { |i| pairs[i] }
  inputs = inputs_str.empty? ? [] : inputs_str.split
  Statement.new(shape, outputs, outputs_types, kind, specifier, inputs)
end

def serialize_statement_seq(seq)
  seq.stmts.map { |s| "#{serialize_statement(s)};\n" }.join
end

def deserialize_statement_seq(s)
  raw_stmts = s.split(';').map(&:strip).reject(&:empty?)
  stmts = raw_stmts.map { |raw| deserialize_statement(raw) }
  StatementSeq.new(stmts)
end
