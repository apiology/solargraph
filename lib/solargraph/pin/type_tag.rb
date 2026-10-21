# frozen_string_literal: true

module Solargraph
  module Pin
    # A YARD tag written from a pin's return type. It renders the type for
    # documentation and keeps the type itself, so readers need not parse the
    # text back -- YARD cannot spell every type, e.g. an RBS intersection.
    class TypeTag < YARD::Tags::Tag
      # The type the tags declare, taken from each TypeTag rather than
      # parsed from its text.
      #
      # @param tags [::Array<YARD::Tags::Tag>]
      # @return [ComplexType]
      def self.complex_type_of tags
        return ComplexType.new(tags.map(&:complex_type)) if !tags.empty? && tags.all?(TypeTag)

        types = tags.map(&:types).flatten.compact
        return ComplexType::UNDEFINED if types.empty?

        ComplexType.try_parse(*types)
      end

      # @return [ComplexType]
      attr_reader :complex_type

      # @param tag_name [::Symbol]
      # @param text [String]
      # @param complex_type [ComplexType]
      def initialize tag_name, text, complex_type
        super(tag_name, text, complex_type.items.map(&:rooted_tag))
        @complex_type = complex_type
      end
    end
  end
end
