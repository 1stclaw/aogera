# frozen_string_literal: true

module Aogera
  module Content
    class Directory
      attr_reader :root

      def initialize(root)
        @root = File.expand_path(root).freeze
      end

      def exist?(path)
        File.file?(physical_path(path))
      end

      def read(path)
        path = VirtualPath.normalize(path)
        File.binread(physical_path(path, normalized: true))
      rescue Errno::ENOENT, Errno::ENOTDIR
        raise NotFound, "content not found: #{path}"
      end

      private

      def physical_path(path, normalized: false)
        path = VirtualPath.normalize(path) unless normalized
        File.join(@root, *path.split("/"))
      end
    end
  end
end
