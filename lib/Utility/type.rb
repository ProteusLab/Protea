module Utility
    # The instances of the Type class are immutable.
    # Only one instance of a particular type is ever created
    # and this instance is linked to one symbol. If two types
    # are equal is a matter of doing a trivial symbol comparison.
    class Type
        attr_reader :name, :bitsize, :typeof
        def initialize(name, bitsize, typeof)
            @name = name; @bitsize = bitsize; @typeof = typeof; @sym = name.to_sym
        end
    end

    $ExistingTypes = {}

    # Returns the Type object associated with the symbol.
    # Currently supported types: signed/unsigned integral, bit type, register type
    # (like pointer in C++/C)
    # If symbol is not [usbr][1-9][0-9]* the behaviour is undefined
    #
    # get_type :b33 -> #<Utility::Type: @bitsize=33, @name="b33", @typeof=:b>
    # get_type :i32 -> #<Utility::Type: @bitsize=32, @name="i32", @typeof=:i>
    # get_type :u64 -> #<Utility::Type: @bitsize=64, @name="u64", @typeof=:u>
    def get_type(sym)
        if $ExistingTypes.has_key?(sym)
            return $ExistingTypes[sym]
        end
        sym_str = sym.to_s
        $ExistingTypes[sym] = Type.new(sym_str, sym_str.scan(/\d+/).last.to_i, sym_str[0].to_sym)
        return $ExistingTypes[sym]
    end

    # Checks if two symbols have the same underlying type.
    # If symbol is not [usbr][1-9][0-9]* the behaviour is undefined
    #
    # equal_typeof :i32 :i36 -> true
    # equal_typeof :u32 :i36 -> false
    def equal_typeof(sym1, sym2)
        return get_type(sym1).typeof == get_type(sym2).typeof
    end

private_constant :Type
module_function :get_type, :equal_typeof
end
