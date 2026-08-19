# frozen_string_literal: true

module Solargraph
  class ComplexType
    module TypeMethods
      # How a type spells out its type parameters (`Hash{K => V}`,
      # `Array(A, B)`, `Array<T>`), and how that shape is rendered back
      # into a tag.
      #
      # Mixed into TypeMethods, alongside which it is included.
      #
      # @abstract This mixin relies on these -
      #   instance variables:
      #     @subtypes: Array<ComplexType>
      #     @key_types: Array<ComplexType>
      #   methods:
      #     name()
      #     subtypes()
      module ParameterShape
        # @!method name
        #   @return [String]
        # @!method subtypes
        #   @return [Array<ComplexType>]

        # @return [Symbol, nil]
        attr_reader :parameters_type

        # @type [Hash{String => Symbol}]
        PARAMETERS_TYPE_BY_STARTING_TAG = {
          '{' => :hash,
          '(' => :fixed,
          '<' => :list
        }.freeze

        # @return [Boolean]
        def list_parameters?
          parameters_type == :list
        end

        # @return [Boolean]
        def fixed_parameters?
          parameters_type == :fixed
        end

        # @return [Boolean]
        def hash_parameters?
          parameters_type == :hash
        end

        # @return [Array<ComplexType>]
        def value_types
          @subtypes
        end

        # @return [Array<ComplexType>]
        def key_types
          @key_types
        end

        # @return [String]
        def substring
          @substring ||= generate_substring_from(:tags)
        end

        # @return [String]
        def rooted_substring
          @rooted_substring = generate_substring_from(:rooted_tags)
        end

        # @param to_str [::Symbol] message that renders a subtype as a tag
        # @return [String]
        def generate_substring_from to_str
          key_types_str = key_types.map(&to_str).join(', ')
          subtypes_str = subtypes.map(&to_str).join(', ')
          if (key_types.none?(&:defined?) && subtypes.none?(&:defined?)) ||
             (key_types.empty? && subtypes.empty?)
            ''
          elsif hash_parameters?
            "{#{key_types_str} => #{subtypes_str}}"
          elsif fixed_parameters?
            "(#{subtypes_str})"
          elsif name == 'Hash'
            "<#{key_types_str}, #{subtypes_str}>"
          else
            "<#{key_types_str}#{subtypes_str}>"
          end
        end
      end
    end
  end
end
