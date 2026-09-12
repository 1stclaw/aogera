# frozen_string_literal: true

module Aogera
  module Content
    Error = Class.new(StandardError)
    NotFound = Class.new(Error)
    InvalidPath = Class.new(Error)
  end
end
