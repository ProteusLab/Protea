# frozen_string_literal: true

module Plod
  module Backend
    class PacketPolicy
      DEFAULTS = {
        latency: 'pioDelay', width: nil, check: 'assert', response: 'normal',
        read_response: 'after_payload', write_response: 'after_dispatch', match: 'first',
        unmapped: 'panic', denied: 'panic', atomic_swap: false, after_write: [], forward: nil
      }.freeze
      ENUMS = {
        check: %w[assert panic], response: %w[normal atomic], read_response: %w[after_payload before_payload],
        write_response: %w[after_dispatch before_dispatch], match: %w[first all],
        unmapped: %w[panic ignore], denied: %w[panic warn ignore]
      }.freeze

      def initialize(raw)
        raise Plod::Error, 'packet policy must be a mapping' unless raw.is_a?(Hash)

        data = raw.transform_keys(&:to_sym)
        unknown = data.keys - DEFAULTS.keys
        raise Plod::Error, "unknown packet policy keys: #{unknown.join(', ')}" unless unknown.empty?

        @data = DEFAULTS.merge(data)
        ENUMS.each do |name, choices|
          raise Plod::Error, "invalid packet #{name}: #{@data[name]}" unless choices.include?(@data[name])
        end
        unless @data[:width].nil? || [1, 2, 4, 8].include?(@data[:width])
          raise Plod::Error, 'packet width must be 1, 2, 4 or 8 bytes'
        end
        unless [true, false].include?(@data[:atomic_swap]) && @data[:after_write].is_a?(Array)
          raise Plod::Error, 'packet atomic_swap must be boolean and after_write must be an array'
        end

        validate_latency(@data[:latency])
        @data[:after_write].each { |name| validate_name(name) }
        validate_forward unless @data[:forward].nil?
      end

      def [](name) = @data[name]

      private

      def validate_name(name)
        return if name.is_a?(String) && name.match?(/\A[a-z_]\w*\z/)

        raise Plod::Error, "invalid packet reference: #{name.inspect}"
      end

      def validate_latency(value)
        return if value.is_a?(Integer) && value >= 0

        validate_name(value)
      end

      def validate_forward
        raw = @data[:forward]
        raise Plod::Error, 'packet forward must be a mapping' unless raw.is_a?(Hash)

        forward = raw.transform_keys(&:to_sym)
        unless forward.keys.sort == %i[start receiver read write latency].sort &&
               forward[:start].is_a?(Integer) && forward[:start] >= 0
          raise Plod::Error, 'packet forward requires start, receiver, read, write and latency'
        end

        %i[receiver read write].each { |name| validate_name(forward[name]) }
        validate_latency(forward[:latency])
        @data[:forward] = forward
      end
    end
  end
end
