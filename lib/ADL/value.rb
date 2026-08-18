module SimInfra
    # Value class is a super class of Variable or Constant.
    class Value
        # If value is nil then Value represents a variable.
        attr_reader :name, :type, :value
        def initialize(name, type, value_num)
            @name = name; @type = type; @value = value_num
        end
        def inspect 
            if @value.nil? 
                "#{@type}:#{@name}";
            else
                "#{@value.to_s(2)}";
            end
        end

        def to_h
            {
                name: @name,
                type: @type,
                value: @value,
            }
        end

        def self.from_h(h)
            Value.new(h[:name], h[:type], h[:value])
        end
    end

    class Constant
        attr_reader :scope, :name, :type, :value
        def initialize(scope, name, value);
            @const = value; @scope = scope; @type = :iconst; @value = value
        end
        def let(other); raise "Assign to constant"; end
        def inspect; "#{@name}:#{@type} (#{@scope.object_id}) {=#{@const}}"; end

        def to_h
            {
                name: @name,
                type: @type,
                value: @value,
           }
        end

        def self.from_h(h, scope)
            Constant.new(scope, h[:name], h[:value])
        end
    end
end