# frozen_string_literal: true

require 'parser'

module Solargraph
  class Source
    class Chain
      class Literal < Link
        attr_reader :word, :value

        # @param type [String]
        # @param node [Parser::AST::Node, Object]
        def initialize type, node
          super("<#{type}>")

          if node.is_a?(::Parser::AST::Node)
            # rubocop:disable Lint/BooleanSymbol -- :true and :false are
            # Parser::AST::Node type names, not booleans
            if node.type == :true
              @value = true
            elsif node.type == :false
              # rubocop:enable Lint/BooleanSymbol
              @value = false
            elsif %i[int sym str].include?(node.type)
              @value = node.children.first
            end
          end
          @type = type
          @literal_type = ComplexType.try_parse(@value.inspect)
          @complex_type = ComplexType.try_parse(type)
        end

        protected def equality_fields
          super + [@value, @type, @literal_type, @complex_type]
        end

        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base]
        # @param locals [::Array<Pin::Base>]
        # @param _receiver_path [::Array<String>, nil]
        def resolve api_map, name_pin, locals, _receiver_path = nil
          if api_map.super_and_sub?(@complex_type.name, @literal_type.name)
            [Pin::ProxyType.anonymous(@literal_type, source: :chain)]
          else
            # we don't support this value as a literal type
            [Pin::ProxyType.anonymous(@complex_type, source: :chain)]
          end
        end
      end
    end
  end
end
