# frozen_string_literal: true

module Aogera
  class Prototype
    class Catalog
      def initialize(prototypes)
        @prototypes = prototypes.each_with_object({}) do |prototype, result|
          name = prototype.name.to_sym
          if result.key?(name)
            raise ArgumentError, "duplicate prototype: #{name.inspect}"
          end

          result[name] = prototype
        end.freeze
      end

      def fetch(name)
        @prototypes.fetch(name)
      end

      def include?(name)
        @prototypes.key?(name)
      end

      def names
        @prototypes.keys.freeze
      end
    end

    module Definitions
    end
  end
end
