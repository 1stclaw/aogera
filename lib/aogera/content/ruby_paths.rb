# frozen_string_literal: true

module Aogera
  module Content
    module RubyPaths
      ROOT = File.expand_path("../../../content", __dir__).freeze

      module_function

      def prototype(name)
        ruby_source("prototypes", name)
      end

      def level(name)
        ruby_source("levels", name)
      end

      def dialogue(name)
        ruby_source("dialogue", name)
      end

      def ruby_source(directory, name)
        File.join(ROOT, directory, "#{name}.rb")
      end
      private_class_method :ruby_source
    end
  end
end
