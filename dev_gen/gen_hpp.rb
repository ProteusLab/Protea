module DevGen
  @binop = [
    :or,
    :mul,
    :add,
    :and,
    :eq,
    :sub,
    :gt,
    :ge
  ]

  @unop = [
    :cast,
    :not
  ]

  @devdesc = nil
  @self = nil
  @tmphash = {}
  @regtypes = {}

  def self.reset
    @devdesc = nil
    @self = nil
    @tmphash = {}
    @regtypes = {}
  end

  def self.gen_cpp_btype(size)
    return :uint8_t if size <= 8
    return :uint32_t if size <= 32

    :uint64_t
  end

  def self.gen_cpp_type(type)
    if type.start_with?('ptr')
      nested_type = type[4..-2]
      type = "#{nested_type}*"
    end
    if type.start_with?('ref')
      nested_type = type[4..-2]
      type = "#{nested_type}&"
    end
    if type.match?(/\Ab\d+\z/)
      type = gen_cpp_btype(type.to_s.delete_prefix('b').to_i)
    end
    if type.match?(/\Arf\d+\z/)
      type = gen_cpp_btype(type.to_s.delete_prefix('rf').to_i)
    end
    type
  end

  def self.indent(text, amount = 4)
    text.gsub(/^/, ' ' * amount)
  end

  def self.gen_enums(enums)
    enums.map { |name, enum| gen_enum(name, enum) }.join('\n\n')
  end

  def self.gen_enum(name, enum)
    enum = <<~CPP
      enum #{name}
      {
      #{indent(enum.map { |key, value| "#{key} = #{value}," }.join("\n"))}
      };
    CPP

    enum
  end

  def self.gen_methods(methods)
    methods.map { |name, method| gen_method(name, method) }.join("\n")
  end

  def self.gen_method(name, desc)
    method = <<~CPP
      #{desc[:ret].nil? ? 'void' : gen_cpp_type(desc[:ret])} #{name}(#{desc[:args].map { |argname, argtype| "#{gen_cpp_type(argtype)} #{argname}" }.join(', ')}) {
      #{indent(gen_scope(desc[:body]))}
      }
    CPP

    method
  end

  def self.gen_regs_methods(regs)
    regs.map { |name, desc| gen_reg_methods(name, desc) }.join("\n")
  end

  def self.gen_reg_methods(reg_name, reg_desc)
    @self = reg_name
    reg_size = reg_desc[:size] * 8
    methods = reg_desc[:methods]

    reg_methods = methods.map { |name, desc| gen_method("#{reg_name}_#{name}", desc) }.join("\n")

    reg_methods += "\n"

    if !methods.key?(:read)
      reg_methods += "#{gen_cpp_btype(reg_size)} #{@self}_read() { return #{@self}; }\n\n" 
    end

    if !methods.key?(:write)
      reg_methods += "void #{@self}_write(#{gen_cpp_btype(reg_size)} data) { #{@self} = data; }\n\n" 
    end

    reg_methods
  end

  def self.gen_scope(desc)
    desc[:tree].map { |sos| sos.key?(:tree) ? gen_scope(sos) : gen_stmt(sos) }.join("\n")
  end

  def self.gen_stmt(desc)
    # puts desc
    stmt = "unsupported"
    if (desc[:name] == :new_var)
      if desc[:oprnds][0][:type].start_with?('ref') || desc[:oprnds][0][:name].start_with?('_tmp')
        stmt = ''
      else
        stmt = <<~CPP.chomp
          #{gen_cpp_type(desc[:oprnds][0][:type])} #{desc[:oprnds][0][:name]};
        CPP
      end
    end

    if (desc[:name] == :get_reg_field)
      lhs = desc[:oprnds][0][:name]
      rhs = desc[:oprnds][1][:name]
      field = @devdesc[:registers][rhs][:fields][desc[:oprnds][2]]
      stmt = <<~CPP.chomp
        #{lhs} = protea::_extract(#{rhs}, #{field[:lsb]}, #{field[:size]});
      CPP
    end

    if (desc[:name] == :set_cntr_elem)
      cntr = desc[:oprnds][0][:name]
      idx = gen_op(desc[:oprnds][1])
      val = gen_op(desc[:oprnds][2])

      stmt = <<~CPP.chomp
        #{cntr}[#{idx}] = #{val};
      CPP
    end

    if (desc[:name] == :get_cntr_elem)
      tmp = desc[:oprnds][0][:name]
      cntr = gen_op(desc[:oprnds][1])
      idx = gen_op(desc[:oprnds][2])

      if tmp.start_with?('_tmp')
        stmt = ''
        @tmphash[tmp] = "#{cntr}[#{idx}]"
      else
        stmt = <<~CPP.chomp
          #{tmp} = #{cntr}[#{idx}];
        CPP
      end
    end

    if (desc[:name] == :get_field)
      tmp = desc[:oprnds][0][:name]
      obj = desc[:oprnds][1][:name]
      field = desc[:oprnds][2]

      get_op = '.'
      get_op = '->' if desc[:oprnds][1][:type].start_with?('ptr')

      prolog = ''
      prolog = "#{gen_cpp_type(desc[:oprnds][0][:type])} " if desc[:oprnds][0][:type].start_with?('ref')

      @tmphash[tmp] = "#{obj}#{get_op}#{field}"
      stmt = ''
    end

    if (desc[:name] == :if)
      cond = desc[:oprnds][0]
      body = desc[:oprnds][1]

      stmt = <<~CPP.chomp
        if (#{gen_op(cond)}) {
        #{indent(gen_scope(body))}
        }
      CPP
    end

    if (desc[:name] == :elseif)
      cond = desc[:oprnds][0]
      body = desc[:oprnds][1]

      stmt = <<~CPP.chomp
        else if (#{gen_op(cond)}) {
        #{indent(gen_scope(body))}
        }
      CPP
    end

    if (desc[:name] == :else)
      body = desc[:oprnds][0]

      stmt = <<~CPP.chomp
        else {
        #{indent(gen_scope(body))}
        }
      CPP
    end

    if (desc[:name] == :for)
      iter = desc[:oprnds][0]
      start = gen_op(desc[:oprnds][1])
      finish = gen_op(desc[:oprnds][2])
      body = desc[:oprnds][3]

      stmt = <<~CPP.chomp
        for (#{iter} < #{start};#{iter} < #{finish}; #{iter}++) {
        #{indent(gen_scope(body))}
        }
      CPP
    end

    if (desc[:name] == :voidmembercall)
      mfname = desc[:oprnds][1]
      obj = gen_op(desc[:oprnds][0])
      args = desc[:oprnds][2..].map { |op| gen_op(op) }

      if (@regtypes.key?(desc[:oprnds][0][:type]))
        stmt = <<~CPP.chomp
          #{desc[:oprnds][0][:name]}_#{mfname}(#{args.join(', ')});
        CPP
      else
        call_op = '.'
        call_op = '->' if desc[:oprnds][0][:type].start_with?('ptr')

        stmt = <<~CPP.chomp
          #{obj}#{call_op}#{mfname}(#{args.join(', ')});
        CPP
      end
    end

    if (desc[:name] == :membercall)
      rettemp = desc[:oprnds][0][:name] 
      mfname = desc[:oprnds][2]
      obj = gen_op(desc[:oprnds][1])
      args = desc[:oprnds][3..].map { |op| gen_op(op) }

      if mfname == :at
        if rettemp.start_with?('_tmp')
          stmt = ''
          @tmphash[rettemp] = "#{obj}[#{args.join(', ')}]"
        else
          stmt = <<~CPP.chomp
            #{rettemp} = #{obj}[#{args.join(', ')}];
          CPP
        end
      else
        call_op = '.'
        call_op = '->' if desc[:oprnds][1][:type].start_with?('ptr')

        if rettemp.start_with?('_tmp')
          stmt = ''
          @tmphash[rettemp] = "#{obj}#{call_op}#{mfname}(#{args.join(', ')})"
        else
          stmt = <<~CPP.chomp
            #{rettemp} = #{obj}#{call_op}#{mfname}(#{args.join(', ')});
          CPP
        end
      end
    end

    if (desc[:name] == :call)
      rettemp = desc[:oprnds][0][:name]
      mfname = desc[:oprnds][1]
      args = desc[:oprnds][2..].map { |op| gen_op(op) }

      stmt = <<~CPP.chomp
        #{rettemp} = #{mfname}(#{args.join(', ')});
      CPP
    end

    if (desc[:name] == :voidcall)
      mfname = desc[:oprnds][0]
      args = desc[:oprnds][1..].map { |op| gen_op(op) }

      stmt = <<~CPP.chomp
        #{mfname}(#{args.join(', ')});
      CPP
    end

    if (@binop.include?(desc[:name]))
      retvar = desc[:oprnds][0][:name]
      lhs = desc[:oprnds][1]
      rhs = desc[:oprnds][2]

      @tmphash[retvar] = "protea::_#{desc[:name]}(#{gen_op(lhs)}, #{gen_op(rhs)})"
      stmt = ""
    end

    if (@unop.include?(desc[:name]))
      retvar = desc[:oprnds][0][:name]
      op = desc[:oprnds][1][:name]

      stmt = <<~CPP.chomp
        #{retvar} = protea::_#{desc[:name]}(#{op});
      CPP
    end

    if (desc[:name] == :let)
      lhs = desc[:oprnds][0]
      rhs = desc[:oprnds][1]

      if (lhs[:type].match?(/\Arf\d+\z/))
        if lhs[:name].start_with?('_tmp')
          stmt = ''
          @tmphash[lhs[:name]] = gen_op(rhs)
        else
          reg_name = @self
          field_info = @devdesc[:registers][@self][:fields][lhs[:name]]
          if field_info.nil?
            owner = @devdesc[:registers].find { |_, rd| rd[:fields].key?(lhs[:name]) }
            unless owner.nil?
              reg_name, reg_desc = owner
              field_info = reg_desc[:fields][lhs[:name]]
            end
          end
          stmt = "protea::_insert(#{reg_name}, #{field_info[:lsb]}, #{field_info[:size]}, #{gen_op(rhs)});"
        end
      else
        if lhs[:name].start_with?('_tmp')
          stmt = ''
          @tmphash[lhs[:name]] = gen_op(rhs)
        else
          stmt = "#{gen_op(lhs)} = #{gen_op(rhs)};"
        end
      end
    end

    if (desc[:name] == :ret)
      stmt = <<~CPP.chomp
        return;
      CPP

      if (!desc[:oprnds].empty?)
        op = desc[:oprnds][0]

        stmt = <<~CPP.chomp
          return #{gen_op(op)};
        CPP
      end
    end

    if (desc[:name] == :get_ptr)
      lhs = desc[:oprnds][0][:name]
      rhs = desc[:oprnds][1][:name]

      stmt = <<~CPP.chomp
        #{lhs} = &#{rhs};
      CPP
    end

    if desc[:name] == :get_enum_value
      tmp = desc[:oprnds][0][:name]
      enum = desc[:oprnds][1]
      key = desc[:oprnds][2]

      stmt = <<~CPP.chomp
        #{tmp} = #{enum}::#{key};
      CPP
    end

    stmt
  end

  def self.gen_op(desc)
    if desc.is_a?(Hash)
      if desc[:type] == :iconst
        if desc[:value].is_a?(String)
          return "\"#{desc[:value]}\""
        end
        return desc[:value]
      end

      op_name = desc[:name]

      return @self if op_name == :self
      return 'sim_clock::as_int::ns' if op_name == :ns

      return @tmphash[op_name] if op_name.start_with?('_tmp')

      return op_name
    end

    return "\"#{desc}\"" if desc.is_a?(String)

    desc
  end

  def self.gen_lambdas(lambdas)
    lambdas.map { |name, lambda| gen_lambda(name, lambda) }.join("\n")
  end

  def self.gen_lambda(name, lambda)
    <<~CPP
      std::function<void()> #{name} = [this] (#{lambda[:args].map { |arg_name, arg_type| "#{arg_type} #{arg_name}" }.join(', ')}) {
      #{indent(gen_scope(lambda[:body]))}
      };
    CPP
  end

  def self.gen_fields(fields)
    fields.map { |name, type_with_args| gen_field(name, type_with_args) }.join("\n")
  end

  def self.gen_field(name, type_with_args)
    type_desc = gen_cpp_type(type_with_args[:type])
    if !type_with_args[:init_args].empty?
      if type_desc == :auto
        return "#{type_desc} #{name} = #{type_with_args[:init_args].map { |arg| gen_op(arg) }.join(', ')};"
      end
      return "#{type_desc} #{name} = #{type_desc}(#{type_with_args[:init_args].map { |arg| gen_op(arg) }.join(', ')});"
    end
    return "#{type_desc} #{name};"
  end

  def self.gen_regs(regs)
    regs.map { |name, desc| gen_reg(name, desc) }.join("\n")
  end

  def self.gen_reg(name, desc)
    if desc.key?(:seqn)
      return "std::array<#{gen_cpp_btype(desc[:size] * 8)}, #{desc[:seqn]}> #{name};"
    end
    "#{gen_cpp_btype(desc[:size] * 8)} #{name} = 0;"
  end

  def self.gen_consts(consts)
    consts.map { |name, desc| gen_const(desc[:type], name, desc[:val]) }.join("\n")
  end

  def self.gen_const(type, name, value)
    "#{gen_cpp_type(type)} #{name} = #{gen_op(value)};"
  end

  def self.gen_reg_read_switch(regs)
    res = ''
    regs.map do |name, desc|
      next if desc[:type] == :wo

      seqn = desc.key?(:seqn) ? desc[:seqn] : 1

      offset = desc[:offset]
      bytesize = desc[:size]
      size = bytesize * 8
      seqsize = bytesize * seqn

      res += <<~CPP
        if (#{offset} <= daddr && daddr < #{offset} + #{seqsize}) {
          #{gen_cpp_btype(size)} read_data;
          #{desc.key?(:enableIf) ? gen_scope(desc[:enableIf]) : ''}
          uint64_t cid = (daddr - #{offset}) / #{bytesize};
          if (#{desc.key?(:enableIf) ? desc[:enableIf][:tree].last[:oprnds][0][:name] : 'true'}) {
            read_data = #{name}_read(#{desc.key?(:seqn) ? 'cid' : ''});
            std::memcpy(data_ptr, &read_data, #{bytesize});
          }
        }
      CPP
    end
    res
  end

  def self.gen_reg_write_switch(regs)
    res = ''
    regs.map do |name, desc|
      next if desc[:type] == :wo

      seqn = desc.key?(:seqn) ? desc[:seqn] : 1

      offset = desc[:offset]
      bytesize = desc[:size]
      size = bytesize * 8
      seqsize = bytesize * seqn

      res += <<~CPP
        if (#{offset} <= daddr && daddr < #{offset} + #{seqsize}) {
          #{gen_cpp_btype(size)} write_data;
          std::memcpy(&write_data, data_ptr, #{bytesize});
          #{desc.key?(:enableIf) ? gen_scope(desc[:enableIf]) : ''}
          uint64_t cid = (daddr - #{offset}) / #{bytesize};
          if (#{desc.key?(:enableIf) ? desc[:enableIf][:tree].last[:oprnds][0][:name] : 'true'}) {
            #{name}_write(write_data#{desc.key?(:seqn) ? ', cid' : ''});
          }
        }
      CPP
    end
    res
  end

  def self.gen_ctor_init_list(desc)
    return '' if desc.nil? || desc[:body].nil?

    @self = :this
    gen_scope(desc[:body])
    desc[:body][:tree].filter { |sos| sos[:name] == :voidcall && sos[:oprnds][0] == :Init }.map { |sos| "#{sos[:oprnds][1]}(#{sos[:oprnds][2..].map { |oper| gen_op(oper)}.join(', ')})" }.join(', ')
  end

  def self.gen_ctor_body(desc)
    return '' if desc.nil? || desc[:body].nil?

    body = desc[:body][:tree].find { |stmt| stmt[:name] == :body }
    return '' if body.nil?

    indent(gen_scope(body[:oprnds][0]), 8)
  end

  def self.gen_header(name, desc, spec)
    reset
    @devdesc = desc

    desc[:registers].map { |name, desc| @regtypes[desc[:type].to_sym] = name }

    ctor_init_list = gen_ctor_init_list(desc[:ctor])
    ctor_init_str = ctor_init_list.to_s.empty? ? '' : ", #{ctor_init_list}"

    header = <<~CPP
      #pragma once

      #{spec.prolog}

      namespace protea {
        auto _or(auto lhs, auto rhs) {
          return lhs | rhs;
        }

        auto _mul(auto lhs, auto rhs) {
          return lhs * rhs;
        }

        auto _add(auto lhs, auto rhs) {
          return lhs + rhs;
        }

        auto _and(auto lhs, auto rhs) {
          return lhs & rhs;
        }

        auto _eq(auto lhs, auto rhs) {
          return lhs == rhs;
        }

        auto _sub(auto lhs, auto rhs) {
          return lhs - rhs;
        }

        auto _gt(auto lhs, auto rhs) {
          return lhs > rhs;
        }

        auto _not(auto op) {
          return ~op;
        }

        bool _cast(auto op) {
          return op > 0;
        }

        template <typename BVTD, typename BVTS>
        void _insert(BVTD& dist, uint32_t lsb, uint32_t size, BVTS src) {
          BVTD cleaner = ~((((BVTD)1 << size) - 1) << lsb);
          BVTS data = ((BVTD)src & (((BVTD)1 << size) - 1)) << lsb;

          dist &= cleaner;
          dist |= data;
        }

        template <typename BVT>
        BVT _extract(BVT op, uint32_t lsb, uint32_t size) {
          return (op >> lsb) & (((BVT)1 << size) - 1);
        }
      }

      namespace gem5 {

      class Terminal;
      class Platform;

      class #{name} : public #{spec.base} {

      #{indent(gen_enums(desc[:enums]))}

      #{indent(gen_consts(desc[:consts]))}

      #{indent(gen_lambdas(desc[:lambdas]))}

      #{indent(gen_fields(desc[:fields]))}

      #{indent(gen_regs(desc[:registers]))}

      #{indent(gen_regs_methods(desc[:registers]))}

      public:

      #{indent(gen_methods(desc[:methods]))}

          #{name}(const #{name}Params &params)
            : #{spec.base}(params, params.pio_size)#{ctor_init_str} {
      #{gen_ctor_body(desc[:ctor])}
            }

          Tick read(PacketPtr pkt) override {
            uint64_t daddr = pkt->getAddr() - pioAddr;
            uint8_t* data_ptr = pkt->getPtr<uint8_t>();

      #{indent(gen_reg_read_switch(desc[:registers]), 6)}

            bool is_atomic = pkt->isAtomicOp() && pkt->cmd == MemCmd::SwapReq;

            if (is_atomic) {
                (*(pkt->getAtomicOp()))(pkt->getPtr<uint8_t>());
                return write(pkt);
            } else {
                pkt->makeResponse();
                return pioDelay;
            }
          }

          Tick write(PacketPtr pkt) {
            Addr daddr = pkt->getAddr() - pioAddr;
            uint8_t* data_ptr = *pkt->getPtr<uint8_t>();

      #{indent(gen_reg_write_switch(desc[:registers]), 6)}

            pkt->makeResponse();
            return pioDelay;
          }

          AddrRangeList getAddrRanges() const
          {
              AddrRangeList ranges;
              ranges.push_back(RangeSize(pioAddr, pioSize));
              return ranges;
          }

          void serialize(CheckpointOut &cp) const override {}
          void unserialize(CheckpointIn &cp) override {}

          Port &
          #{name}::getPort(const std::string &if_name, PortID idx)
          {
#{indent(spec.port_body, 8)}
          }

          void
          #{name}::init()
          {
#{indent(spec.init_body, 8)}
          }
      };

      }
    CPP

    header
  end
end
