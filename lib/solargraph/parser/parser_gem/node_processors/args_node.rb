# frozen_string_literal: true

module Solargraph
  module Parser
    module ParserGem
      module NodeProcessors
        class ArgsNode < Parser::NodeProcessor::Base
          def process
            callable = region.closure
            if callable.is_a? Pin::Callable
              if node.type == :forward_args
                forward(callable)
              else
                node.children.each do |u|
                  if u.type == :mlhs
                    process_mlhs_param(callable, u)
                    next
                  end
                  loc = get_node_location(u)
                  locals.push Solargraph::Pin::Parameter.new(
                    location: loc,
                    closure: callable,
                    comments: comments_for(node),
                    name: u.children[0].to_s,
                    assignment: u.children[1],
                    # @sg-ignore Need to add nil check here
                    asgn_code: u.children[1] ? region.code_for(u.children[1]) : nil,
                    # @sg-ignore Need to add nil check here
                    presence: callable.location.range,
                    decl: get_decl(u),
                    # a default value expression is only assigned
                    # conditionally (when the caller omits the arg),
                    # so it shouldn't be treated as a guaranteed
                    # override of the declared @param type
                    definite: false,
                    source: :parser
                  )
                  # @sg-ignore Wrong argument type for Array#push: objects expected Solargraph::Pin::Parameter, received Solargraph::Pin::LocalVariable, nil
                  callable.parameters.push locals.last
                end
              end
            end
            process_children
          end

          private

          # @param callable [Pin::Callable]
          # @return [void]
          def forward callable
            loc = get_node_location(node)
            locals.push Solargraph::Pin::Parameter.new(
              location: loc,
              closure: callable,
              # @sg-ignore Need to add nil check here
              presence: region.closure.location.range,
              decl: get_decl(node),
              source: :parser
            )
            # @sg-ignore Wrong argument type for Array#push: objects expected Solargraph::Pin::Parameter, received Solargraph::Pin::LocalVariable, nil
            callable.parameters.push locals.last
          end

          # @param node [AST::Node]
          # @return [Symbol]
          def get_decl node
            node.type
          end

          # A destructured parameter group (`|(a, b), c|`). The group
          # itself occupies one position in the block signature; the
          # variables inside it are locals whose types are projected from
          # the group's tuple type by element position (see
          # Pin::Parameter#mlhs_path).
          #
          # @param callable [Pin::Callable]
          # @param mlhs_node [AST::Node]
          # @return [void]
          def process_mlhs_param callable, mlhs_node
            loc = get_node_location(mlhs_node)
            locals.push Solargraph::Pin::Parameter.new(
              location: loc,
              closure: callable,
              comments: comments_for(node),
              name: region.code_for(mlhs_node) || '()',
              # @sg-ignore Need to add nil check here
              presence: callable.location.range,
              decl: :mlhs,
              source: :parser
            )
            # @sg-ignore Wrong argument type for Array#push - locals.last is the
            #   Parameter pushed just above; post-merge inference sees LocalVariable, nil
            callable.parameters.push locals.last
            add_mlhs_locals callable, mlhs_node, [callable.parameters.length - 1]
          end

          # @param callable [Pin::Callable]
          # @param mlhs_node [AST::Node]
          # @param path [::Array<Integer>]
          # @return [void]
          def add_mlhs_locals callable, mlhs_node, path
            mlhs_node.children.each_with_index do |child, i|
              if child.type == :mlhs
                add_mlhs_locals callable, child, path + [i]
              else
                loc = get_node_location(child)
                locals.push Solargraph::Pin::Parameter.new(
                  location: loc,
                  closure: callable,
                  comments: comments_for(node),
                  name: child.children[0].to_s,
                  # @sg-ignore Need to add nil check here
                  presence: callable.location.range,
                  decl: :arg,
                  mlhs_path: path + [i],
                  source: :parser
                )
              end
            end
          end
        end
      end
    end
  end
end
