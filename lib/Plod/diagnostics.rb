# frozen_string_literal: true

module Plod
  class Loc
    attr_reader :path, :line

    def initialize(path, line)
      @path = path
      @line = line
    end

    def self.capture
      entry = caller_locations.find { |l| !l.path.to_s.include?('lib/Plod') }
      return nil if entry.nil?

      new(entry.path, entry.lineno)
    end

    def to_s
      return '(unknown)' if @path.nil?

      @line ? "#{@path}:#{@line}" : @path.to_s
    end

    def to_h
      [path, line]
    end

    def self.from_h(h)
      return nil if h.nil?

      new(h[0], h[1])
    end

    def ==(other)
      other.is_a?(Loc) && other.path == @path && other.line == @line
    end
  end

  class Diagnostic
    LEVELS = %i[error warning].freeze

    attr_reader :level, :message, :loc

    def initialize(level, message, loc = nil)
      raise ArgumentError, "invalid level: #{level}" unless LEVELS.include?(level)

      @level = level
      @message = message
      @loc = loc
    end

    def error? = @level == :error

    def to_s
      loc_s = loc ? "#{loc}: " : ''
      "#{loc_s}#{level}: #{message}"
    end
  end

  class DiagnosticBag
    include Enumerable

    def initialize
      @diagnostics = []
    end

    def error(message, loc = nil)
      @diagnostics << Diagnostic.new(:error, message, loc)
      nil
    end

    def warning(message, loc = nil)
      @diagnostics << Diagnostic.new(:warning, message, loc)
      nil
    end

    def <<(diagnostic)
      @diagnostics << diagnostic
    end

    def merge!(other)
      @diagnostics.concat(other.to_a)
      self
    end

    def each(&) = @diagnostics.each(&)

    def empty? = @diagnostics.empty?

    def errors = @diagnostics.select(&:error?)

    def error? = errors.any?

    def to_s
      @diagnostics.map(&:to_s).join("\n")
    end
  end

  class Error < StandardError
    attr_reader :diagnostic

    def initialize(message, loc = nil)
      @diagnostic = Diagnostic.new(:error, message, loc)
      super(message)
    end
  end
end
