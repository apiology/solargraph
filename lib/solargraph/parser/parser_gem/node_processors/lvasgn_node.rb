# frozen_string_literal: true

module Solargraph
  module Parser
    module ParserGem
      module NodeProcessors
        class LvasgnNode < Parser::NodeProcessor::Base
          include ParserGem::NodeMethods

          def process
            # s(:lvasgn, name, value) - value is absent in an mlhs or a rescue
            node => [:lvasgn, Symbol => name, *rest]
            assignment = (rest in [::Parser::AST::Node => value, *]) ? value : nil

            here = get_node_start_position(node)
            # @sg-ignore Unresolved call to range on Solargraph::Location, nil
            presence = Range.new(here, region.closure.location.range.ending)
            loc = get_node_location(node)
            locals.push Solargraph::Pin::LocalVariable.new(
              location: loc,
              closure: region.closure,
              name: name.to_s,
              assignment: assignment,
              comments: comments_for(node),
              type_assertion: type_assertion_for(node),
              presence: presence,
              # false inside an if/while/rescue body, which may not run
              definite: !region.compound_statement.conditional,
              compound_statement: region.compound_statement,
              source: :parser
            )
            process_children
          end
        end
      end
    end
  end
end
