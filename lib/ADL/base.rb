require_relative "value"
# Testing infra

module SimInfra
    # @@instructions -array of instruction description
    # shows result of our tests in interactive Ruby (IRB) or standalone
    def self.serialize(msg= nil)
        require 'yaml'
        yaml_data = YAML.dump(
          {
            regfiles: @@regfiles.map(&:to_h),
            interface_functions: @@interface_functions.map(&:to_h),
            instructions: @@instructions.map(&:to_h),
          }
        )
        yaml_data
    end

    def self.state
        yaml_data = YAML.dump(
            {
                regfiles: @@regfiles.map(&:to_h),
                interface_functions: @@interface_functions.map(&:to_h),
                instructions: @@instructions.map(&:to_h),
            }
        )
    end

    # reset state
    def siminfra_reset_module_state; @@instructions = []; end

    # mixin for global counter, function returns 0,1,2,....
    module GlobalCounter
        @@counter = -1
        def next_counter; @@counter += 1; end
    end

    class Field
        attr_reader :from, :to, :value
        def initialize(from, to, value)
            @from = from; @to = to; @value = value;
        end

        def to_h
            {
                from: @from,
                to: @to,
                value: {
                    name: @value.name,
                    type: @value.type,
                    value_num: @value.value,
                }
            }
        end

        def self.from_h(h)
            Field.new(h[:from], h[:to], Value.new(h[:value][:name], h[:value][:type], h[:value][:value_num]))
        end
    end

    ImmFieldPart = Struct.new(:name, :from, :to, :hi, :lo)

    def field(name, from, to, value_num = nil)
        Field.new(from, to, Value.new(name, ("b" + (from - to + 1).to_s).to_sym, value_num)).freeze
    end
    def immpart(name, from, to, hi, lo)
        ImmFieldPart.new(name, from, to, hi, lo).freeze
    end

    def assert(condition, msg = nil); raise msg if !condition; end
end
