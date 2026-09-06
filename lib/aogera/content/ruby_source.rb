# frozen_string_literal: true

module Aogera
  module Content
    module RubySource
      module_function

      def absolute_path(path, kind:)
        absolute_path = File.expand_path(path)

        unless File.extname(absolute_path) == ".rb"
          raise ArgumentError,
            "unsupported #{kind} source: #{absolute_path}"
        end

        absolute_path
      end

      def constant_name_for(path)
        File.basename(path, ".rb")
          .split("_")
          .map!(&:capitalize)
          .join
      end
    end
  end
end
