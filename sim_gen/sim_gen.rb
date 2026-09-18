#!/usr/bin/ruby
# frozen_string_literal: true

require 'sim_gen/CPUState/cpu_state'
require 'sim_gen/Decoders/decoder'
require 'sim_gen/ISA/isa'
require 'sim_gen/ExecEngines/naive_interpreter'
require 'sim_gen/ExecEngines/base_exec_engine'
require 'sim_gen/Hart/hart'
require 'sim_gen/ExecEngines/llvm_jit'

require 'yaml'

yaml_data = YAML.load_file(ARGV[0])
architecture_name = yaml_data[:architecture_name] || 'RISC-V'
yaml_data[:architecture_name] = architecture_name
yaml_data[:isa_name] = architecture_name.gsub(/[^0-9A-Za-z]/, '')

File.write('cpu_state.hh', SimGen::CPUState::Header.generate_cpu_state(yaml_data))
File.write('base_exec_engine.hh', SimGen::BaseExecEngine::Header.generate_base_exec_engine(yaml_data))
File.write('base_exec_engine.cc', SimGen::BaseExecEngine::TranslationUnit.generate_base_exec_engine(yaml_data))
File.write('naive_interpreter.hh', SimGen::NaiveInterpreter::Header.generate_naive_interpreter(yaml_data))
File.write('naive_interpreter.cc', SimGen::NaiveInterpreter::TranslationUnit.generate_naive_interpreter(yaml_data))
File.write('decoder.hh', SimGen::Decoder::Header.generate_decoder(yaml_data))
File.write('decoder.cc', SimGen::Decoder::TranslationUnit.generate_decoder(yaml_data))
File.write('isa.hh', SimGen::ISA::Header.generate_isa_header(yaml_data))
File.write('hart.hh', SimGen::Hart::Header.generate_hart(yaml_data))
File.write('hart.cc', SimGen::Hart::TranslationUnit.generate_hart(yaml_data))
