# frozen_string_literal: true

module Solargraph
  module Convention
    module DataDefinition
      # A node wrapper for a Data definition via const assignment.
      # @example
      #   MyData = Data.new(:bar, :baz) do
      #     def foo
      #     end
      #   end
      class DataAssignmentNode < DataDefintionNode
        class << self
          # @example
          # s(:casgn, nil, :Foo,
          #   s(:block,
          #     s(:send,
          #       s(:const, nil, :Data), :define,
          #       s(:sym, :bar),
          #       s(:sym, :baz)),
          #     s(:args),
          #     s(:def, :foo,
          #       s(:args),
          #       s(:send, nil, :bar))))
          # @param node [::Parser::AST::Node]
          # @return [Boolean]
          def match? node
            return false unless node&.type == :casgn
            return false if node.children[2].nil?

            # @sg-ignore Unresolved call to type on Parser::AST::Node, nil
            data_node = if node.children[2].type == :block
                          # @sg-ignore Unresolved call to children on Parser::AST::Node, nil
                          node.children[2].children[0]
                        else
                          node.children[2]
                        end

            # @sg-ignore Wrong argument type for Solargraph::Convention::DataDefinition::DataDefintionNode.data_definition_node?: data_node expected Parser::AST::Node, received Parser::AST::Node, nil
            data_definition_node?(data_node)
          end
        end

        # @return [Object]
        def class_name
          if node.children[0]
            # @sg-ignore Wrong argument type for Solargraph::Parser::ParserGem::NodeMethods.unpack_name: node expected Parser::AST::Node, received Parser::AST::Node, nil
            Parser::NodeMethods.unpack_name(node.children[0]) + "::#{node.children[1]}"
          else
            node.children[1].to_s
          end
        end

        private

        # @return [Parser::AST::Node]
        # @sg-ignore Declared return type ::Parser::AST::Node does not match inferred type ::Parser::AST::Node, nil for Solargraph::Convention::DataDefinition::DataAssignmentNode#data_node
        def data_node
          # @sg-ignore Unresolved call to type on Parser::AST::Node, nil
          if node.children[2].type == :block
            # @sg-ignore Unresolved call to children on Parser::AST::Node, nil
            node.children[2].children[0]
          else
            node.children[2]
          end
        end
      end
    end
  end
end
