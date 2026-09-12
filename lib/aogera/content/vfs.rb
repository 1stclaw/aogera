# frozen_string_literal: true

module Aogera
  module Content
    class VFS
      def initialize
        @sources = []
      end

      def mount(source)
        @sources << source
        nil
      end

      def exist?(path)
        path = VirtualPath.normalize(path)
        @sources.reverse_each.any? { |source| source.exist?(path) }
      end

      def read(path)
        path = VirtualPath.normalize(path)

        @sources.reverse_each do |source|
          begin
            return source.read(path)
          rescue NotFound
            next
          end
        end

        raise NotFound, "content not found: #{path}"
      end
    end
  end
end
