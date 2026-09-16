# frozen_string_literal: true

module Solargraph
  module Parser
    module ParserGem
      module NodeProcessors
        class OrasgnNode < Parser::NodeProcessor::Base
          include ParserGem::NodeMethods

          # @return [void]
          def process
            closure_location = region.closure.location
            if closure_location
              here = get_node_start_position(node)
              presence = Range.new(here, closure_location.range.ending)
              FlowSensitiveTyping.new(locals, ivars, enclosing_breakable_pin,
                                      enclosing_compound_statement_pin, region.closure).process_or_asgn(node, presence)
            end

            # @sg-ignore Need to add nil check here
            new_node = node.updated(node.children[0].type, node.children[0].children + [node.children[1]])
            # `x ||= y` assigns only when x is falsy, so it never overrides
            # x's prior type.
            asgn_cs = Solargraph::Pin::CompoundStatement.new(
              location: get_node_location(node),
              closure: region.closure,
              compound_statement: region.compound_statement,
              conditional: true,
              node: node,
              source: :parser
            )
            pins.push asgn_cs
            NodeProcessor.process(new_node, region.update(compound_statement: asgn_cs), pins, locals, ivars)
          end
        end
      end
    end
  end
end
