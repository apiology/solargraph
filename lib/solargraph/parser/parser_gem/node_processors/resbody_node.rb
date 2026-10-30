# frozen_string_literal: true

module Solargraph
  module Parser
    module ParserGem
      module NodeProcessors
        class ResbodyNode < Parser::NodeProcessor::Base
          include ParserGem::NodeMethods

          # @return [void]
          def process
            # s(:resbody, s(:array, *exception_classes) | nil, s(:lvasgn, name) | nil, body)
            node => [:resbody,
                     ::Parser::AST::Node | nil => exceptions,
                     ::Parser::AST::Node | nil => variable,
                     ::Parser::AST::Node | nil => body]

            rescue_body_cs = Solargraph::Pin::CompoundStatement.new(
              # an empty clause has no body node; fall back to the
              # clause itself, since SourceMap expects located pins
              location: get_node_location(body || node),
              closure: region.closure,
              compound_statement: region.compound_statement,
              conditional: true,
              node: body,
              source: :parser
            )
            pins.push rescue_body_cs
            # variable is an lvasgn, ivasgn, cvasgn or gvasgn (Symbol name), a
            # send for `=> a.b` (receiver node) or a casgn for `=> A` (nil scope)
            if variable in [_, Symbol | ::Parser::AST::Node | nil => variable_name, *]
              # @sg-ignore Wrong argument type for Solargraph::Parser::ParserGem::NodeMethods#get_node_start_position: node expected Parser::AST::Node, received Parser::AST::Node, nil
              here = get_node_start_position(variable)
              # @sg-ignore Unresolved call to range on Solargraph::Location, nil
              presence = Range.new(here, region.closure.location.range.ending)
              # @sg-ignore Wrong argument type for Solargraph::Parser::NodeProcessor::Base#get_node_location: node expected Parser::AST::Node, received Parser::AST::Node, nil
              loc = get_node_location(variable)
              types = if exceptions.nil?
                        ['Exception']
                      else
                        exceptions.children.map do |child|
                          # @sg-ignore Wrong argument type for Solargraph::Parser::ParserGem::NodeMethods#unpack_name: node expected Parser::AST::Node, nil,
                          #   received Parser::AST::Node, Integer, Float, Rational, Complex, String, Symbol, NilClass
                          unpack_name(child)
                        end
                      end
              locals.push Solargraph::Pin::LocalVariable.new(
                location: loc,
                closure: region.closure,
                name: variable_name.to_s,
                comments: "@type [#{types.join(',')}]",
                presence: presence,
                # bound only when this rescue clause runs
                definite: false,
                compound_statement: rescue_body_cs,
                source: :parser
              )
            end
            NodeProcessor.process(body, region.update(compound_statement: rescue_body_cs), pins, locals, ivars) if body
          end
        end
      end
    end
  end
end
