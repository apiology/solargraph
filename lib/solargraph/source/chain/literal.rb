# frozen_string_literal: true

require 'parser'

module Solargraph
  class Source
    class Chain
      class Literal < Link
        attr_reader :word

        # The literal's own type (e.g. `"a"`) for a string literal, else
        # undefined; see Chain#argument_type.
        #
        # @return [ComplexType]
        attr_reader :literal_type

        # @return [::String, ::Symbol]
        attr_reader :value

        # @return [Parser::AST::Node]
        attr_reader :node

        # @param type [String]
        # @param node [Parser::AST::Node, Object]
        def initialize type, node
          super("<#{type}>")
          @node = node

          if node.is_a?(::Parser::AST::Node)
            if node.type == :true
              @value = true
            elsif node.type == :false
              @value = false
            # @sg-ignore flow sensitive typing needs to narrow down type with an if is_a? check
            elsif %i[int sym str].include?(node.type)
              @value = node.children.first
            end
          end
          @type = type
          # @sg-ignore Unresolved call to type on Parser::AST::Node, Object
          @literal_type = if node.is_a?(::Parser::AST::Node) && node.type == :str
                            ComplexType.try_parse(@value.inspect)
                          else
                            ComplexType::UNDEFINED
                          end
          @complex_type = ComplexType.try_parse(type)
        end

        # @sg-ignore Fix "Not enough arguments to Module#protected"
        protected def equality_fields
          # @sg-ignore literal arrays in this module turn into ::Solargraph::Source::Chain::Array
          super + [@value, @type, @literal_type, @complex_type]
        end

        # Resolves to the class (e.g. String), so a variable assigned a
        # literal keeps that class; only argument checks read #literal_type.
        def resolve api_map, name_pin, locals
          [Pin::ProxyType.anonymous(@complex_type, source: :chain)]
        end
      end
    end
  end
end
