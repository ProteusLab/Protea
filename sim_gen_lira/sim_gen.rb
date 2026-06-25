#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.dirname(__FILE__)

require_relative '../lib/lira/arch_ser_yaml'

arch = Lira::ArchSerYaml.read_arch(ARGV[0])
require "Target/#{arch.name}/cpp_ops"

require_relative 'cpp_gen'
require_relative 'base_ops_gen'
require_relative 'snippets_gen'

require_relative 'CPUState/cpu_state'
require_relative 'Decoders/decoder'
require_relative 'ISA/isa'
require_relative 'ExecEngines/naive_interpreter'
require_relative 'ExecEngines/base_exec_engine'
require_relative 'Hart/hart'

LiraCppGen::OpRegistry.ops = arch.operations.to_h { |op| [op.name, op] }

File.write('cpu_state.hh',  SimGen::CPUState::Header.generate_cpu_state(arch))
File.write('base_exec_engine.hh', SimGen::BaseExecEngine::Header.generate_base_exec_engine(arch))
File.write('base_exec_engine.cc', SimGen::BaseExecEngine::TranslationUnit.generate_base_exec_engine(arch))
File.write('naive_interpreter.hh', SimGen::NaiveInterpreter::Header.generate_naive_interpreter(arch))
File.write('naive_interpreter.cc', SimGen::NaiveInterpreter::TranslationUnit.generate_naive_interpreter(arch))
File.write('decoder.hh', SimGen::Decoder::Header.generate_decoder(arch))
File.write('decoder.cc', SimGen::Decoder::TranslationUnit.generate_decoder(arch))
File.write('isa.hh', SimGen::ISA::Header.generate_isa_header(arch))
File.write('hart.hh', SimGen::Hart::Header.generate_hart(arch))
File.write('hart.cc', SimGen::Hart::TranslationUnit.generate_hart(arch))
File.write('base_ops.h', SimGen.generate_base_ops(arch.operations))
File.write('snippets.h', SimGen::Snippets.generate_snippets_header(arch.snippets))
