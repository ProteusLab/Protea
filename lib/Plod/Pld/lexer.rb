# frozen_string_literal: true

module Plod
  module Pld
    # Token stream for .pld device descriptions.
    #
    # Tokens are arrays [type, value, line]. Types: :ident, :int, :string,
    # :punct (value is the operator/bracket itself), :nl, :eof. :int and
    # :string values are hashes { value:, raw: } so the original spelling
    # (0x0A vs 10) survives into the generated Ruby. Newlines are kept as
    # tokens so the parser can treat them as statement terminators.
    class Lexer
      PUNCT = [
        '<<=', '>>=', '&&', '||', '<<', '>>', '<=', '>=', '==', '!=',
        '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=',
        '{', '}', '(', ')', '[', ']', ',', ';', ':', '.', '->',
        '+', '-', '*', '/', '%', '&', '|', '^', '~', '!', '<', '>', '=', '?'
      ].freeze

      def initialize(source, path = '(pld)')
        @source = source
        @path = path
        @pos = 0
        @line = 1
        @tokens = []
      end

      def self.tokenize(source, path = '(pld)')
        new(source, path).tokenize
      end

      def tokenize
        lex_token while @pos < @source.length
        @tokens << [:eof, nil, @line]
        @tokens
      end

      private

      def lex_token
        rest = @source[@pos..]
        case rest
        when /\A[ \t\r]+/, %r{\A(?://|\#)[^\n]*} then skip(Regexp.last_match[0])
        when /\A\n/ then emit(:nl, nil)
        when /\A(?:0[xX][0-9a-fA-F]+|\d+)/ then emit_int(Regexp.last_match[0])
        when /\A"(\\.|[^"\\])*"/ then emit_string(Regexp.last_match[0])
        when /\A[A-Za-z_][A-Za-z0-9_]*/ then emit(:ident, Regexp.last_match[0])
        else
          punct = PUNCT.find { |p| rest.start_with?(p) }
          error("unexpected character '#{rest[0]}'") if punct.nil?

          emit(:punct, punct)
        end
      end

      def skip(text)
        @line += text.count("\n")
        @pos += text.length
      end

      def emit(type, text)
        @tokens << [type, text, @line]
        @pos += text.nil? ? 1 : text.length
      end

      def emit_int(raw)
        @tokens << [:int, { value: Integer(raw), raw: raw }, @line]
        @pos += raw.length
      end

      def emit_string(raw)
        @tokens << [:string, { value: unescape(raw), raw: raw }, @line]
        @pos += raw.length
      end

      def unescape(raw)
        raw[1..-2].gsub(/\\(.)/) do
          case Regexp.last_match(1)
          when 'n' then "\n"
          when 't' then "\t"
          else Regexp.last_match(1)
          end
        end
      end

      def error(msg)
        raise Plod::Error.new("#{@path}:#{@line}: #{msg}", nil)
      end
    end
  end
end
