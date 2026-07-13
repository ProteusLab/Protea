#!/usr/bin/env ruby
# frozen_string_literal: true

# instr_info_gen_lira/instr_info_gen.rb
# Entry point: reads the LIRA IR (lira.yaml) and generates the C++ instruction
# info header (LLVM-MCInstrDesc-like) into the current directory.

require_relative '../lib/lira/arch_ser_yaml'
require_relative 'header_gen'

arch = Lira::ArchSerYaml.read_arch(ARGV[0])
File.write('instr_info.hh', InstrInfoGen::Header.generate(arch))
