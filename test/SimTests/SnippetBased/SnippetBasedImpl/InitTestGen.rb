# frozen_string_literal: true

require 'optparse'
require 'yaml'
require 'etc'
require 'parallel'
require 'Utility/gen_emitter'
require_relative 'Target/RISCV/Formatter'

module SimTest
  class InitAsmGen
    attr_reader :ir, :reg2value, :rng

    def initialize(ir, seed: nil)
      @ir = ir
      @seed = seed || Random.new_seed
      @rng = Random.new(@seed)
    end

    def seed; @seed; end

    def generate_random_values
      values = {}
      ir[:regfiles].each do |regfile|
        regfile[:regs].each do |reg|
          attrs = reg[:attrs] || []
          next if attrs.include?(:zero) || attrs.include?(:pc)
          size = reg[:size] || 32
          max = (1 << size) - 1
          values[reg[:name]] = @rng.rand(0..max)
        end
      end
      values
    end

    def generate(formatter, snippet_content, output_file)
      emitter = Utility::GenEmitter.new()
      @reg2value = generate_random_values

      formatter.prologue(emitter)
      formatter.init_register(emitter, ir, @reg2value)

      emitter.emit_line 'j _snippet'
      emitter.decrease_indent
      emitter.emit_line '_snippet:'
      emitter.increase_indent
      formatter.insert_snippet(emitter, snippet_content)
      emitter.emit_line 'j _exit_snippet'
      emitter.decrease_indent
      emitter.emit_line '_exit_snippet:'
      emitter.increase_indent

      formatter.epilogue(emitter)

      File.write("#{output_file}yaml", @reg2value.to_yaml)
      File.write("#{output_file}s", emitter.to_s)
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  options = {
    num_tests: 4,
    seed: 42,
    jobs: Etc.nprocessors
  }

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: #{$PROGRAM_NAME} [options] <ir_yaml> <snippets_dir> <output_dir>"

    opts.on('-n', '--num-tests NUM', Integer, 'Number of tests per snippet (default: 4)') do |n|
      options[:num_tests] = n
    end

    opts.on('-s', '--seed SEED', Integer, 'Random seed for reproducibility') do |s|
      options[:seed] = s
    end

    opts.on('-j', '--jobs NUM', Integer, 'Number of parallel workers (default: CPU count)') do |j|
      options[:jobs] = j
    end

    opts.on('-h', '--help', 'Show this help message') do
      puts opts
      exit
    end
  end

  parser.parse!

  if ARGV.size != 3
    puts parser
    exit 1
  end

  ir_file, snippets_dir, output_directory = ARGV

  ir = YAML.load_file(ir_file, symbolize_names: true)

  snippet_paths = Dir.glob(File.join(snippets_dir, '*')).select { |p| File.file?(p) }

  jobs = snippet_paths.each_with_index.flat_map do |snippet_path, snippet_idx|
    snippet_content = File.read(snippet_path)
    base = File.basename(snippet_path, '.*')

    options[:num_tests].times.map do |i|
      {
        ir: ir,
        snippet_content: snippet_content,
        base: base,
        i: i,
        num_tests: options[:num_tests],
        seed: options[:seed] + snippet_idx * options[:num_tests] + i,
        output_directory: output_directory
      }
    end
  end

  Parallel.each(jobs, in_processes: options[:jobs]) do |job|
    formatter = SimTest::RiscVFormatter.new
    generator = SimTest::InitAsmGen.new(job[:ir], seed: job[:seed])

    output_file = File.join(job[:output_directory], "#{job[:base]}_#{job[:i]}.init.")
    generator.generate(formatter, job[:snippet_content], output_file)

    puts "Generated: #{output_file}s (seed: #{generator.seed}, test #{job[:i] + 1}/#{job[:num_tests]})"
  end
end
