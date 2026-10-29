# frozen_string_literal: true

module Solargraph
  class Source
    class Chain
      class Array < Literal
        # @param children [::Array<Chain>]
        # @param node [Parser::AST::Node]
        def initialize children, node
          super('::Array', node)
          @children = children
        end

        def word
          @word ||= "<#{@type}>"
        end

        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base]
        # @param locals [::Array<Pin::Parameter, Pin::LocalVariable>]
        def resolve api_map, name_pin, locals
          [Pin::ProxyType.anonymous(infer_type(api_map, name_pin, locals), source: :chain)]
        end

        protected

        # @sg-ignore Fix "Not enough arguments to Module#protected"
        def equality_fields
          # @sg-ignore literal arrays in this module turn into ::Solargraph::Source::Chain::Array
          super + [@children]
        end

        private

        # Infer Array<T>, with T the union of the elements' non-literal
        # types.  Tuples and literal types need an explicit YARD or RBS
        # declaration, so neither is inferred here.
        #
        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base]
        # @param locals [::Array<Pin::Parameter, Pin::LocalVariable>]
        # @return [ComplexType::UniqueType]
        def infer_type api_map, name_pin, locals
          bare = ComplexType::UniqueType.new('Array', rooted: true)
          return bare if @children.empty? || @children.any?(&:splat?)
          element_types = @children.map { |child| child.infer(api_map, name_pin, locals) }
          return bare if element_types.any?(&:undefined?)
          subtypes = element_types.flat_map { |type| type.simplify_literals.items }.uniq
          ComplexType::UniqueType.new('Array', [], subtypes, rooted: true, parameters_type: :list)
        end
      end
    end
  end
end
