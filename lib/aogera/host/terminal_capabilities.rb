# frozen_string_literal: true

module Aogera
  module Host
    class TerminalCapabilities
      KITTY_TERMS = [
        "xterm-kitty",
        "kitty"
      ].freeze

      def self.detect(env: ENV)
        kitty = kitty_terminal?(env)

        Capabilities.new(
          graphics_protocol: kitty ? :kitty : nil,
          keyboard_protocol: kitty ? :kitty : :legacy
        )
      end

      def self.kitty_terminal?(env)
        return true if present?(env["KITTY_WINDOW_ID"])

        term = env["TERM"].to_s.downcase
        KITTY_TERMS.any? { |name| term.include?(name) }
      end
      private_class_method :kitty_terminal?

      def self.present?(value)
        value && !value.empty?
      end
      private_class_method :present?
    end
  end
end
