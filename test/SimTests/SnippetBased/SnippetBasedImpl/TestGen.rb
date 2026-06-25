# frozen_string_literal: true

require 'yaml'
require 'etc'
require 'parallel'
require 'optparse'
require 'Utility/gen_emitter'
require_relative 'Target/RISCV/Formatter'
require_relative 'Parsers/QEMUParser'

module SimTest
  class FinalAsmGen
    attr_reader :ir

    def initialize(ir)
      @ir = ir
    end

    def generate(formatter, snippet_content, init_yaml_file, ref_log_file, output_file)
      emitter = Utility::GenEmitter.new

      initreg2value = YAML.load_file(init_yaml_file)
      refreg2value = QEMULogParser.parse(ref_log_file)

      formatter.prologue(emitter)
      formatter.init_register(emitter, @ir, initreg2value)

      emitter.emit_line 'j _snippet'
      emitter.decrease_indent
      emitter.emit_line '_snippet:'
      emitter.increase_indent
      formatter.insert_snippet(emitter, snippet_content)
      emitter.emit_line 'j _exit_snippet'
      emitter.decrease_indent
      emitter.emit_line '_exit_snippet:'
      emitter.increase_indent

      formatter.insert_check(emitter, @ir, refreg2value)

      formatter.epilogue(emitter)
      File.write(output_file, emitter.to_s)
    end
  end
end

if __FILE__ == $0
  options = {
    jobs: Etc.nprocessors
  }

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options] <ir_yaml_file> <snippets_dir> <init_yaml_dir> <log_dir> <output_dir>"

    opts.on('-j', '--jobs NUM', Integer, 'Number of parallel workers (default: CPU count)') do |j|
      options[:jobs] = j
    end

    opts.on('-h', '--help', 'Show this help message') do
      puts opts
      exit
    end
  end

  parser.parse!

  if ARGV.size != 5
    puts parser
    exit 1
  end

  ir_file = ARGV[0]
  snippets_dir = ARGV[1]
  init_yaml_dir = ARGV[2]
  log_dir = ARGV[3]
  output_dir = ARGV[4]

  ir = YAML.load_file(ir_file, symbolize_names: true)

  snippet_map = Dir.glob(File.join(snippets_dir, '*'))
                   .select { |f| File.file?(f) }
                   .each_with_object({}) do |path, map|
    map[File.basename(path, '.*')] = path
  end

  log_files = Dir.glob(File.join(log_dir, '*')).select { |f| File.file?(f) }

  jobs = log_files.filter_map do |log_path|
    log_basename = File.basename(log_path)
    match = log_basename.match(/^(.*)_(\d+)\.init\.log$/)

    snippet = match[1]
    index = match[2].to_i

    snippet_path = snippet_map[snippet]

    init_yaml_file = File.join(init_yaml_dir, "#{snippet}_#{index}.init.yaml")

    {
      ir: ir,
      snippet: snippet,
      index: index,
      snippet_path: snippet_path,
      init_yaml_file: init_yaml_file,
      log_path: log_path,
      output_file: File.join(output_dir, "#{snippet}_#{index}.s")
    }
  end

  Parallel.each(jobs, in_processes: options[:jobs]) do |job|
    generator = SimTest::FinalAsmGen.new(job[:ir])
    formatter = SimTest::RiscVFormatter.new
    snippet_content = File.read(job[:snippet_path])

    generator.generate(
      formatter,
      snippet_content,
      job[:init_yaml_file],
      job[:log_path],
      job[:output_file]
    )

    puts "Generated: #{job[:output_file]}"
  end
end
