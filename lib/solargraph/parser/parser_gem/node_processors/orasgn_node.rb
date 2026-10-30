# frozen_string_literal: true

module Solargraph
  module Parser
    module ParserGem
      module NodeProcessors
        class OrasgnNode < Parser::NodeProcessor::Base
          include ParserGem::NodeMethods

          # @return [void]
          def process
            # s(:or_asgn, s(:lvasgn, name), value) is processed as s(:lvasgn, name, value)
            node => [:or_asgn,
                     ::Parser::AST::Node[Symbol => target_type, *target_children],
                     ::Parser::AST::Node => value]

            closure_location = region.closure.location
            if closure_location
              here = get_node_start_position(node)
              presence = Range.new(here, closure_location.range.ending)
              FlowSensitiveTyping.new(locals, ivars, enclosing_breakable_pin,
                                      enclosing_compound_statement_pin).process_or_asgn(node, presence)
            end

            new_node = node.updated(target_type, target_children + [value])
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
