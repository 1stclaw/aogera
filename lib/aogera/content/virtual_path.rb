# frozen_string_literal: true

module Aogera
  module Content
    module VirtualPath
      module_function

      def normalize(path)
        unless path.is_a?(String)
          raise InvalidPath, "content path must be a String"
        end
        if path.empty?
          raise InvalidPath, "content path must not be empty"
        end
        if path.include?("\0")
          raise InvalidPath, "content path must not contain NUL"
        end

        normalized = path.tr("\\", "/")
        if normalized.start_with?("/") || normalized.match?(/\A[A-Za-z]:/)
          raise InvalidPath, "content path must be relative: #{path.inspect}"
        end
        if normalized.end_with?("/")
          raise InvalidPath, "content path must name a file: #{path.inspect}"
        end

        segments = normalized.split("/", -1)
        segments.reject!(&:empty?)
        if segments.empty?
          raise InvalidPath, "content path must not be empty"
        end
        if segments.any? { |segment| segment == "." || segment == ".." }
          raise InvalidPath, "content path must not contain . or .. segments: #{path.inspect}"
        end

        segments.join("/")
      end
    end
  end
end
