# frozen_string_literal: true

require_relative 'lexer'

module Plod
  module Pld
    # Recursive-descent parser for .pld device descriptions.
    #
    # The dialect is deliberately forgiving: statements may be terminated by
    # either ';' or a newline (the reference file mixes both), '//' and '#'
    # start line comments, and unary '&' is the address-of operator.
    # Blank lines between declarations and statements are recorded (:blank)
    # so the translator can preserve the source's paragraph structure.
    class Parser
      BUILTIN_TYPES = %w[bool int string auto void].freeze
      BUILTIN_RE = /\Ab\d+\z/

      PRECEDENCE = {
        '||' => 5, '&&' => 7, '|' => 10, '^' => 15, '&' => 20,
        '==' => 25, '!=' => 25, '<' => 30, '<=' => 30, '>' => 30, '>=' => 30,
        '<<' => 35, '>>' => 35, '+' => 40, '-' => 40,
        '*' => 50, '/' => 50, '%' => 50
      }.freeze

      ASSIGN_OPS = ['=', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '<<=', '>>='].freeze

      # -- AST ----------------------------------------------------------------
      TypeRef = Struct.new(:name, :pointer, :array_size, keyword_init: true)
      Param = Struct.new(:type, :name, keyword_init: true)
      StructDecl = Struct.new(:name, :abstract, :items, :blank, keyword_init: true)
      ObjectDecl = Struct.new(:type, :name, keyword_init: true)
      FunctionDecl = Struct.new(:ret, :name, :args, keyword_init: true)
      DeviceDecl = Struct.new(:name, :decls, keyword_init: true)
      EnumDecl = Struct.new(:name, :pairs, :blank, keyword_init: true)
      ConstDecl = Struct.new(:type, :name, :value, :blank, keyword_init: true)
      MethodDecl = Struct.new(:ret, :name, :args, :body, :abstract, :blank, keyword_init: true)
      RegisterDecl = Struct.new(:name, :props, :items, :blank, keyword_init: true)
      EnableIf = Struct.new(:expr, :blank, keyword_init: true)
      RegFieldDecl = Struct.new(:name, :lo, :hi, :blank, keyword_init: true)
      FieldDecl = Struct.new(:type, :name, :init, :abstract, :blank, keyword_init: true)
      IfStmt = Struct.new(:cond, :then_body, :elsif_list, :else_body, :blank, keyword_init: true)
      ReturnStmt = Struct.new(:expr, :blank, keyword_init: true)
      VarStmt = Struct.new(:type, :name, :init, :blank, keyword_init: true)
      AssignStmt = Struct.new(:target, :op, :value, :blank, keyword_init: true)
      ExprStmt = Struct.new(:expr, :blank, keyword_init: true)
      IntLit = Struct.new(:token, keyword_init: true)
      StrLit = Struct.new(:token, keyword_init: true)
      Ident = Struct.new(:name, keyword_init: true)
      BinOp = Struct.new(:op, :lhs, :rhs, keyword_init: true)
      UnOp = Struct.new(:op, :operand, keyword_init: true)
      Member = Struct.new(:recv, :name, keyword_init: true)
      Call = Struct.new(:target, :args, keyword_init: true)
      Lambda = Struct.new(:body, keyword_init: true)
      StaticCast = Struct.new(:type, :expr, keyword_init: true)
      AddrOf = Struct.new(:expr, keyword_init: true)

      def self.parse(source, path = '(pld)')
        new(Lexer.tokenize(source, path), path).parse_program
      end

      def initialize(tokens, path)
        @tokens = tokens
        @path = path
        @i = 0
        @paren_depth = 0
        @type_names = []
      end

      def parse_program
        decls = []
        decls << parse_toplevel until eof?
        Struct.new(:decls).new(decls)
      end

      private

      # -- token stream ---------------------------------------------------------
      # peek/accept/expect work on a newline-skipping view of the stream;
      # newline tokens are consumed only by skip_newlines, so blank lines
      # can be detected by the declaration/statement loops.
      def peek(offset = 0)
        idx = raw_index
        found = 0
        while idx < @tokens.length
          tok = @tokens[idx]
          return tok if tok[0] == :eof || found == offset

          idx += 1
          found += 1
        end
        @tokens.last
      end

      def raw_index
        idx = @i
        idx += 1 while @tokens[idx] && @tokens[idx][0] == :nl
        idx
      end

      def newline_ahead?
        @tokens[@i] && @tokens[@i][0] == :nl
      end

      def newline_run
        run = 0
        idx = @i
        while @tokens[idx] && @tokens[idx][0] == :nl
          run += 1
          idx += 1
        end
        run
      end

      def blank_line_ahead?
        newline_run >= 2
      end

      def skip_newlines
        @i += 1 while @tokens[@i] && @tokens[@i][0] == :nl
      end

      def advance
        idx = raw_index
        tok = @tokens[idx]
        @i = idx + 1
        tok
      end

      def type?(tok)
        tok && tok[0] == :ident &&
          (BUILTIN_TYPES.include?(tok[1]) || tok[1].match?(BUILTIN_RE) || @type_names.include?(tok[1]))
      end

      def eof?
        peek[0] == :eof
      end

      def check(type, value = nil)
        tok = peek
        tok[0] == type && (value.nil? || tok[1] == value)
      end

      def accept(type, value = nil)
        check(type, value) ? advance : nil
      end

      def expect(type, value = nil)
        tok = peek
        return advance if tok[0] == type && (value.nil? || tok[1] == value)

        error("expected #{value || type}, got #{describe(tok)}")
      end

      def describe(tok)
        tok[0] == :eof ? 'end of file' : "'#{tok[1]}'"
      end

      def error(msg)
        raise Plod::Error.new("#{@path}:#{peek[2]}: #{msg}", nil)
      end

      def end_statement
        accept(:punct, ';')
      end

      # -- declarations ----------------------------------------------------------
      def parse_toplevel
        if check(:ident, 'abstract')
          advance
          return parse_struct(abstract: true) if accept(:ident, 'struct')

          parse_abstract_binding
        elsif accept(:ident, 'struct')
          parse_struct(abstract: false)
        elsif check(:ident, 'device')
          parse_device
        else
          error("expected a declaration, got #{describe(peek)}")
        end
      end

      # 'abstract Tick ns;' or 'abstract Tick curTick();'
      def parse_abstract_binding
        type = parse_type
        name = expect(:ident)[1]
        decl =
          if accept(:punct, '(')
            args = parse_params
            expect(:punct, ')')
            FunctionDecl.new(ret: type, name: name, args: args)
          else
            ObjectDecl.new(type: type, name: name)
          end
        end_statement
        decl
      end

      def parse_struct(abstract:)
        name = expect(:ident)[1]
        @type_names << name
        items = parse_braced_items { parse_struct_member }
        StructDecl.new(name: name, abstract: abstract, items: items)
      end

      def parse_struct_member
        type = parse_type
        name = expect(:ident)[1]
        array_size = parse_array_suffix
        if accept(:punct, '(')
          args = parse_params
          expect(:punct, ')')
          body = accept(:punct, ';') ? nil : parse_block
          MethodDecl.new(ret: type, name: name, args: args, body: body, abstract: body.nil?)
        else
          init = accept(:punct, '=') ? parse_expr : nil
          decl = FieldDecl.new(type: with_array(type, array_size), name: name, init: init, abstract: false)
          end_statement
          decl
        end
      end

      def parse_device
        expect(:ident, 'device')
        name = expect(:ident)[1]
        decls = parse_braced_items { parse_device_decl }
        DeviceDecl.new(name: name, decls: decls)
      end

      def parse_device_decl
        case peek[1]
        when 'enum' then parse_enum
        when 'const' then parse_const
        when 'register' then parse_register
        when 'abstract'
          advance
          type = type?(peek) ? parse_type : nil
          name = expect(:ident)[1]
          decl =
            if accept(:punct, '(')
              args = parse_params
              expect(:punct, ')')
              MethodDecl.new(ret: type, name: name, args: args, body: nil, abstract: true)
            else
              FieldDecl.new(type: type, name: name, init: nil, abstract: true)
            end
          end_statement
          decl
        else parse_method_or_field
        end
      end

      def parse_enum
        expect(:ident, 'enum')
        name = expect(:ident)[1]
        @type_names << name
        values = []
        expect(:punct, '{')
        skip_newlines
        until check(:punct, '}')
          key = expect(:ident)[1]
          expect(:punct, ':')
          values << [key, expect(:int)[1]]
          accept(:punct, ',')
          skip_newlines
        end
        expect(:punct, '}')
        end_statement
        EnumDecl.new(name: name, pairs: values)
      end

      def parse_const
        expect(:ident, 'const')
        type = parse_type
        name = expect(:ident)[1]
        expect(:punct, '=')
        value = expect(:int)[1]
        decl = ConstDecl.new(type: type, name: name, value: value)
        end_statement
        decl
      end

      # 'TYPE name(args) { body }' (method) or 'TYPE name = init;' (field)
      def parse_method_or_field
        type = parse_type
        name = expect(:ident)[1]
        array_size = parse_array_suffix
        if accept(:punct, '(')
          args = parse_params
          expect(:punct, ')')
          body = accept(:punct, ';') ? nil : parse_block
          MethodDecl.new(ret: type, name: name, args: args, body: body, abstract: body.nil?)
        else
          init = accept(:punct, '=') ? parse_expr : nil
          decl = FieldDecl.new(type: with_array(type, array_size), name: name, init: init, abstract: false)
          end_statement
          decl
        end
      end

      def parse_register
        expect(:ident, 'register')
        name = expect(:ident)[1]
        props = []
        if accept(:punct, ':')
          loop do
            prop = expect(:ident)[1]
            expect(:punct, '(')
            arg = parse_prop_arg
            expect(:punct, ')')
            props << [prop, arg]
            break unless accept(:punct, ',')
          end
        end
        items = parse_braced_items { parse_register_item }
        RegisterDecl.new(name: name, props: props, items: items)
      end

      def parse_prop_arg
        tok = peek
        case tok[0]
        when :int then expect(:int)[1]
        when :string then expect(:string)[1]
        when :ident then expect(:ident)[1]
        else error("expected a register property value, got #{describe(tok)}")
        end
      end

      def parse_register_item
        if check(:ident, 'enableIf')
          advance
          expect(:punct, '{')
          expr = parse_expr
          expect(:punct, '}')
          EnableIf.new(expr: expr)
        elsif check(:ident, 'field')
          advance
          name = expect(:ident)[1]
          expect(:punct, '(')
          lo = expect(:int)[1][:raw]
          hi = accept(:punct, ',') ? expect(:int)[1][:raw] : lo
          expect(:punct, ')')
          RegFieldDecl.new(name: name, lo: lo, hi: hi)
        else
          ret = type?(peek) && !type?(peek(1)) ? parse_type : nil
          name = expect(:ident)[1]
          expect(:punct, '(')
          args = parse_params
          expect(:punct, ')')
          body = accept(:punct, ';') ? nil : parse_block
          MethodDecl.new(ret: ret, name: name, args: args, body: body, abstract: false)
        end
      end

      # -- types and parameters ----------------------------------------------------
      def parse_type
        tok = expect(:ident)
        error("'#{tok[1]}' is not a known type; declare the struct/enum before use") unless type?(tok)

        pointer = 0
        pointer += 1 while accept(:punct, '*')
        TypeRef.new(name: tok[1], pointer: pointer, array_size: nil)
      end

      def with_array(type, size)
        return type if size.nil?

        TypeRef.new(name: type.name, pointer: type.pointer, array_size: size)
      end

      def parse_array_suffix
        return nil unless check(:punct, '[')

        advance
        size = expect(:int)[1][:value]
        expect(:punct, ']')
        size
      end

      def parse_params
        args = []
        skip_newlines
        until check(:punct, ')')
          type = parse_type
          name = expect(:ident)[1]
          args << Param.new(type: type, name: name)
          accept(:punct, ',')
          skip_newlines
        end
        args
      end

      # -- statements ----------------------------------------------------------------
      # Shared loop for { }-delimited item lists: detects blank lines before
      # each item, skips separator newlines, stops at the closing brace.
      def parse_braced_items
        expect(:punct, '{')
        items = []
        loop do
          blank = blank_line_ahead?
          skip_newlines
          break if check(:punct, '}') || eof?

          item = yield
          item.blank = blank if item.respond_to?(:blank=)
          items << item
        end
        expect(:punct, '}')
        items
      end

      def parse_block
        parse_braced_items { parse_stmt }
      end

      def parse_stmt
        stmt =
          if check(:ident, 'if')
            parse_if
          elsif check(:ident, 'return')
            parse_return
          elsif looks_like_var_decl?
            parse_var_stmt
          else
            parse_expr_or_assign
          end
        end_statement
        stmt
      end

      def parse_var_stmt
        type = parse_type
        name = expect(:ident)[1]
        init = accept(:punct, '=') ? parse_expr : nil
        VarStmt.new(type: type, name: name, init: init)
      end

      def parse_expr_or_assign
        expr = parse_expr
        op = ASSIGN_OPS.find { |o| check(:punct, o) }
        if op
          advance
          return AssignStmt.new(target: expr, op: op, value: parse_expr)
        end

        ExprStmt.new(expr: expr)
      end

      def looks_like_var_decl?
        type?(peek) && peek(1)[0] == :ident && !type?(peek(1))
      end

      def parse_if
        expect(:ident, 'if')
        expect(:punct, '(')
        cond = parse_expr
        expect(:punct, ')')
        then_body = parse_block
        elsif_list = []
        else_body = nil
        while check(:ident, 'else')
          advance
          if accept(:ident, 'if')
            expect(:punct, '(')
            sub_cond = parse_expr
            expect(:punct, ')')
            elsif_list << [sub_cond, parse_block]
          else
            else_body = parse_block
            break
          end
        end
        IfStmt.new(cond: cond, then_body: then_body, elsif_list: elsif_list, else_body: else_body)
      end

      def parse_return
        expect(:ident, 'return')
        expr = check(:punct, ';') || check(:punct, '}') || newline_ahead? ? nil : parse_expr
        ReturnStmt.new(expr: expr)
      end

      # -- expressions (Pratt) ---------------------------------------------------------
      def parse_expr
        parse_binary(0)
      end

      def parse_binary(min_prec)
        lhs = parse_unary
        loop do
          tok = peek
          prec = PRECEDENCE[tok[1]]
          break if tok[0] != :punct || prec.nil? || prec < min_prec

          # An infix operator must continue the line its left operand ended on.
          break if newline_ahead? && @paren_depth.zero?

          advance
          rhs = parse_binary(prec + 1)
          lhs = BinOp.new(op: tok[1], lhs: lhs, rhs: rhs)
        end
        lhs
      end

      def parse_unary
        tok = peek
        if tok[0] == :punct && %w[~ ! - & *].include?(tok[1])
          advance
          operand = parse_unary
          return AddrOf.new(expr: operand) if tok[1] == '&'

          return UnOp.new(op: tok[1], operand: operand)
        end
        parse_postfix
      end

      def parse_postfix
        expr = parse_primary
        loop do
          if (check(:punct, '.') || check(:punct, '->')) && !newline_ahead?
            advance
            expr = Member.new(recv: expr, name: expect(:ident)[1])
          elsif check(:punct, '(') && !newline_ahead?
            advance
            @paren_depth += 1
            args = []
            skip_newlines
            until check(:punct, ')')
              args << parse_expr
              accept(:punct, ',')
              skip_newlines
            end
            expect(:punct, ')')
            @paren_depth -= 1
            expr = Call.new(target: expr, args: args)
          else
            break
          end
        end
        expr
      end

      def parse_primary
        return parse_lambda if lambda_ahead?

        tok = peek
        case tok[0]
        when :int then IntLit.new(token: expect(:int)[1])
        when :string then StrLit.new(token: expect(:string)[1])
        when :ident
          return parse_static_cast if tok[1] == 'static_cast'

          Ident.new(name: expect(:ident)[1])
        when :punct
          if tok[1] == '('
            advance
            @paren_depth += 1
            expr = parse_expr
            expect(:punct, ')')
            @paren_depth -= 1
            return expr
          end
          error("unexpected #{describe(tok)} in expression")
        else
          error("unexpected #{describe(tok)} in expression")
        end
      end

      def parse_static_cast
        expect(:ident, 'static_cast')
        expect(:punct, '<')
        type = parse_type
        expect(:punct, '>')
        expect(:punct, '(')
        @paren_depth += 1
        expr = parse_expr
        expect(:punct, ')')
        @paren_depth -= 1
        StaticCast.new(type: type, expr: expr)
      end

      def lambda_ahead?
        idx = raw_index
        t1 = @tokens[idx]
        t2 = @tokens[idx + 1]
        t3 = @tokens[idx + 2]
        t1 && t1[0] == :punct && t1[1] == '[' &&
          t2 && t2[0] == :punct && t2[1] == ']' &&
          t3 && t3[0] == :punct && t3[1] == '{'
      end

      def parse_lambda
        expect(:punct, '[')
        expect(:punct, ']')
        Lambda.new(body: parse_block)
      end
    end
  end
end
