# frozen_string_literal: true

module Solargraph
  module Parser
    module ParserGem
      module NodeProcessors
        class ResbodyNode < Parser::NodeProcessor::Base
          include ParserGem::NodeMethods

          # @return [void]
          def process
            exception_local = node.children[1] # Exception local variable name
            if exception_local
              here = get_node_start_position(exception_local)
              # @sg-ignore Need to add nil check here
              presence = Range.new(here, region.closure.location.range.ending)
              loc = get_node_location(exception_local)
              exception_classes_node = node.children[0]
              types = if exception_classes_node.nil?
                        ['Exception']
                      else
                        exception_classes_node.children.map do |child|
                          unpack_name(child)
                        end
                      end
              locals.push Solargraph::Pin::LocalVariable.new(
                location: loc,
                closure: region.closure,
                name: exception_local.children[0].to_s,
                comments: "@type [#{types.join(',')}]",
                presence: presence,
                source: :parser
              )
            end
            # not pushed onto `pins` - and/or/orasgn/resbody bodies are
            # too common to warrant a pin per occurrence, so only the
            # pointer is needed for the compound_statement chain
            rescue_body_node = node.children[2]
            rescue_body_cs = Solargraph::Pin::CompoundStatement.new(
              location: rescue_body_node ? get_node_location(rescue_body_node) : nil,
              closure: region.closure,
              compound_statement: region.compound_statement,
              conditional: true,
              node: rescue_body_node,
              source: :parser
            )
            NodeProcessor.process(rescue_body_node, region.update(compound_statement: rescue_body_cs), pins, locals, ivars) if rescue_body_node
          end
        end
      end
    end
  end
end
