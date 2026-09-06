# frozen_string_literal: true

module Aogera
  module Dialogue
    module Definitions; end

    class Catalog
      def initialize(definitions)
        unless definitions.is_a?(Hash)
          raise ArgumentError, "dialogue definitions must be a Hash"
        end

        @entries = definitions.to_h do |key, lines|
          [key.to_sym, normalize_lines(key, lines)]
        end.freeze
      end

      def fetch(key)
        @entries.fetch(key.to_sym)
      end

      def key?(key)
        @entries.key?(key.to_sym)
      end

      private

      def normalize_lines(key, lines)
        unless lines.is_a?(Array) && !lines.empty?
          raise ArgumentError,
            "dialogue #{key.inspect} must contain at least one line"
        end

        lines.map do |line|
          unless line.is_a?(String) && !line.empty?
            raise ArgumentError,
              "dialogue #{key.inspect} contains an invalid line"
          end

          line.dup.freeze
        end.freeze
      end
    end
  end
end
