# frozen_string_literal: true

module Plod
  class Slate
    KEEP = %i[
      __id__ __send__ object_id instance_eval instance_exec
      method_missing respond_to? respond_to_missing?
      initialize initialize_copy class singleton_class
      inspect to_s == equal? != ! nil? hash is_a? kind_of? instance_of?
      frozen? freeze dup clone raise
    ].freeze

    (instance_methods + private_instance_methods).each do |m|
      undef_method(m) unless KEEP.include?(m)
    end

    def method_missing(name, *args)
      raise Plod::Error.new("unknown name '#{name}'", Plod::Loc.capture)
    end
  end
end
