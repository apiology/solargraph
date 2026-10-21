# frozen_string_literal: true

module Solargraph
  module Pin
    class Constant < BaseVariable
      attr_reader :visibility

      # @param visibility [::Symbol] The visibility of the constant (:public, :protected, or :private)
      # @param splat [Hash] Additional options supported by superclasses
      def initialize visibility: :public, **splat
        super(**splat)
        @visibility = visibility
      end

      def return_type
        @return_type ||= generate_complex_type
      end

      def completion_item_kind
        Solargraph::LanguageServer::CompletionItemKinds::CONSTANT
      end

      # @return [Integer]
      def symbol_kind
        LanguageServer::SymbolKinds::CONSTANT
      end

      def path
        @path ||= context.namespace.to_s.empty? ? name : "#{context.namespace}::#{name}"
      end

      private

      # @return [ComplexType]
      def generate_complex_type
        type = TypeTag.complex_type_of(docstring.tags(:return))
        type = TypeTag.complex_type_of(docstring.tags(:type)) if type.undefined?
        type
      end

      # @return [::Symbol]
      def return_type_tag_name
        :return
      end
    end
  end
end
