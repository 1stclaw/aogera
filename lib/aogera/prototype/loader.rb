# frozen_string_literal: true

module Aogera
  class Prototype
    module Loader
      module_function

      def load(path)
        absolute_path = Content::RubySource.absolute_path(
          path,
          kind: :prototype
        )

        require absolute_path

        definition_name = Content::RubySource.constant_name_for(
          absolute_path
        )
        definitions = Definitions.const_get(definition_name, false)

        Catalog.new(definitions)
      end
    end
  end
end
