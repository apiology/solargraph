# frozen_string_literal: true

module Solargraph
  module Parser
    module ParserGem
      module NodeProcessors
        class IfNode < Parser::NodeProcessor::Base
          include ParserGem::NodeMethods

          def process
            process_children

            FlowSensitiveTyping.new(locals).run(node)
          end
        end
      end
    end
  end
end
