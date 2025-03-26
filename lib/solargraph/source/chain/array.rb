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
        # @param locals [Enumerable<Pin::LocalVariable>]
        def resolve api_map, name_pin, locals
          child_types = @children.map do |child|
            child.infer(api_map, name_pin, locals).simplify_literals
          end
          type = if child_types.length == 0 || child_types.any?(&:undefined?)
                   "::Array"
                 elsif child_types.uniq.length == 1
                   "::Array<#{child_types.first.tags}>"
                 else
                   "::Array(#{child_types.map(&:tags).join(', ')})"
                 end
          [Pin::ProxyType.anonymous(ComplexType.try_parse(type))]
        end
      end
    end
  end
end
