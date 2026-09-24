# frozen_string_literal: true

require 'optparse'

module Plod
  class Cli
    def self.run(argv)
      new(argv).run
    end

    def initialize(argv)
      @argv = argv
      @targets_dir = File.join(root, 'targets')
      @target_name = nil
      @device_name = nil
      @output = nil
      @format = :yaml
    end

    def run
      command = @argv.shift
      case command
      when 'check' then cmd_check
      when 'ir' then cmd_ir
      when 'build' then cmd_build
      when 'translate' then cmd_translate
      when 'targets' then cmd_targets
      when 'version', '--version', '-v' then puts Plod::VERSION
      when 'help', '--help', '-h', nil then print_help
      else
        warn "plod: unknown command '#{command}'"
        print_help
        1
      end
    rescue Plod::Error => e
      warn "plod: error: #{e.message}"
      1
    end

    private

    def root
      @root ||= begin
        spec = Gem.loaded_specs['dsl']
        if spec
          spec.gem_dir
        else
          File.expand_path('..', __dir__)
        end
      end
    end

    def print_help
      puts <<~HELP
        plod — Protea Language fOr Devices toolchain

        usage: plod <command> [options] <device.rb>...

        commands:
          check <file.rb>...      parse and type-check device descriptions
          translate <file.pld>... translate .pld descriptions into Ruby DSL
          ir <file.rb>...         print the device IR (YAML by default)
          build <file.rb>...      generate C++ headers from device descriptions
          targets                 list available target descriptors
          version                 print version

        options for translate:
          -o, --output FILE      write to FILE instead of the sibling .rb ('-' for stdout);
                                  only with a single input file

        options for ir:
          -o, --output FILE       write IR to FILE instead of stdout
          -j, --json              emit JSON instead of YAML

        options for build:
          -o, --output FILE       write header to FILE instead of stdout
          -t, --target NAME       target descriptor name or path (default: auto by device)
          -d, --device NAME       build only this device when a file declares several
      HELP
    end

    def parse_common(opts)
      opts.on('-t NAME', '--target NAME', 'target descriptor name or path') { |v| @target_name = v }
      opts.on('-d NAME', '--device NAME', 'restrict to one device') { |v| @device_name = v.to_sym }
      opts.on('-o FILE', '--output FILE', 'output file') { |v| @output = v }
    end

    def load_and_check(paths)
      paths.map do |path|
        raise Plod::Error, "no such file: #{path}" unless File.exist?(path)

        fe = Plod::Frontend.load_file(path)
        fe.diag.merge!(Plod::Checker.check(fe.program))
        [path, fe]
      end
    end

    def report(diag)
      puts diag unless diag.empty?
      if diag.error?
        warn "plod: #{diag.errors.size} error(s) found"
        return 1
      end
      0
    end

    def cmd_check
      paths = @argv
      raise Plod::Error, 'check: no input files (try: plod check lib/Devices/clint.rb)' if paths.empty?

      status = 0
      load_and_check(paths).each do |path, fe|
        puts "Checking #{path}" if paths.size > 1
        status = 1 if report(fe.diag) == 1
      end
      status
    end

    def cmd_translate
      parse_opts(@argv) { |opts| parse_common(opts) }
      paths = @positional
      raise Plod::Error, 'translate: no input files (try: plod translate lib/Devices/uart8250.pld)' if paths.empty?
      raise Plod::Error, 'translate: -o requires exactly one input file' if @output && paths.size > 1

      paths.each do |path|
        raise Plod::Error, "no such file: #{path}" unless File.exist?(path)
        raise Plod::Error, "translate: expected a .pld file, got '#{path}'" unless path.end_with?('.pld')

        source = Plod::Pld::Translator.translate_file(path)
        target = if @output
                   @output == '-' ? nil : @output
                 else
                   path.sub(/\.pld\z/, '.rb')
                 end
        if target
          File.write(target, source)
          puts "translated #{path} -> #{target}" unless @output == '-'
        else
          print source
        end
      end
      0
    end

    def cmd_ir
      parse_opts(@argv) do |opts|
        opts.on('-j', '--json', 'emit JSON') { @format = :json }
        parse_common(opts)
      end
      paths = @positional
      raise Plod::Error, 'ir: no input files' if paths.empty?

      programs = load_and_check(paths)
      had_errors = programs.any? { |_, fe| fe.diag.error? }
      # rubocop:disable Style/HashEachMethods -- programs is an Array of [path, fe] pairs, not a Hash
      programs.each { |_, fe| puts fe.diag unless fe.diag.empty? }
      # rubocop:enable Style/HashEachMethods
      return 1 if had_errors

      merged = merge_programs(programs)
      payload = @format == :json ? JSON.pretty_generate(dump_json(merged.to_h)) : Plod.yaml_dump(merged.to_h)
      write_out(payload)
      0
    end

    def dump_json(obj)
      case obj
      when Hash then obj.to_h { |k, v| [k.to_s, dump_json(v)] }
      when Array then obj.map { |v| dump_json(v) }
      when Symbol then obj.to_s
      else obj
      end
    end

    def cmd_build
      parse_opts(@argv) { |opts| parse_common(opts) }
      paths = @positional
      raise Plod::Error, 'build: no input files' if paths.empty?

      programs = load_and_check(paths)
      had_errors = programs.any? { |_, fe| fe.diag.error? }
      # rubocop:disable Style/HashEachMethods -- programs is an Array of [path, fe] pairs, not a Hash
      programs.each { |_, fe| puts fe.diag unless fe.diag.empty? }
      # rubocop:enable Style/HashEachMethods
      return 1 if had_errors

      targets = registry
      merged = merge_programs(programs)

      devices = merged.devices
      devices = devices.select { |d| d.name == @device_name } if @device_name
      raise Plod::Error, "device '#{@device_name}' not found" if devices.empty?

      if @output && devices.size > 1
        raise Plod::Error, '-o cannot be used with multiple devices; pass --device to select one'
      end

      devices.each do |device|
        target = pick_target(targets, device)
        header = Plod::Backend::Cpp.generate(merged, device, target)
        if @output
          write_out(header)
        else
          puts header
        end
      end
      0
    end

    def pick_target(targets, device)
      target = if @target_name
                 File.exist?(@target_name) ? Plod::Backend::Target.load(@target_name) : targets[@target_name]
               else
                 targets.for_device(device.name)
               end

      if @target_name
        raise Plod::Error, "unknown target '#{@target_name}' (see: plod targets)" if target.nil?

        unless target.supports_device?(device.name)
          raise Plod::Error, "target '#{target.name}' does not support device '#{device.name}'"
        end
      elsif target.nil?
        raise Plod::Error, "no target supports device '#{device.name}' (see: plod targets)"
      end

      target
    end

    def cmd_targets
      registry.all.each do |t|
        devices = t.devices.empty? ? '(any device)' : t.devices.join(', ')
        puts format('%<name>-16s base=%<base>s  devices=%<devices>s', name: t.name, base: t.base, devices: devices)
      end
      0
    end

    def registry
      Plod::Backend::Target::Registry.new([@targets_dir])
    end

    def merge_programs(programs)
      return programs.first[1].program if programs.size == 1

      merged = Plod::IR::Program.new(path: nil, devices: [], components: [], objects: {}, functions: {})
      # rubocop:disable Style/HashEachMethods -- programs is an Array of [path, fe] pairs, not a Hash
      programs.each do |_path, fe|
        prog = fe.program
        merged.devices.concat(prog.devices)
        merged.components.concat(prog.components)
        merged.objects.merge!(prog.objects)
        merged.functions.merge!(prog.functions)
      end
      # rubocop:enable Style/HashEachMethods
      merged
    end

    def write_out(payload)
      if @output
        File.write(@output, payload)
      else
        puts payload
      end
    end

    def parse_opts(argv)
      @positional = []
      OptionParser.new do |opts|
        yield opts
        opts.on('-h', '--help', 'show help') do
          print_help
          exit 0
        end
      end.parse!(argv)
      @positional.concat(argv)
      @positional
    end
  end
end
