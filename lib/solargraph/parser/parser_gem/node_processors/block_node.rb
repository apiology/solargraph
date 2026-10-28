# frozen_string_literal: true

module Solargraph
  module Parser
    module ParserGem
      module NodeProcessors
        class BlockNode < Parser::NodeProcessor::Base
          include ParserGem::NodeMethods

          def process
            # s(:block, call, args, body)
            node => [:block, ::Parser::AST::Node => call, *]

            location = get_node_location(node)
            scope = region.scope || region.closure.context.scope
            # Foo.class_eval { ... } - s(:send, s(:const, ...), :class_eval, *args)
            if call in [:send, ::Parser::AST::Node[:cbase | :const, *] => clazz, :class_eval, *]
              clazz_name = unpack_name(clazz)
              # instance variables should come from the Class<T> type
              # - i.e., treated as class instance variables
              context = ComplexType.try_parse("Class<#{clazz_name}>")
              scope = :class
            end
            block_pin = Solargraph::Pin::Block.new(
              location: location,
              closure: region.closure,
              compound_statement: region.compound_statement,
              # a block's body may execute zero or multiple times (e.g.
              # Enumerable#each), so an assignment inside it is never
              # guaranteed to have executed
              conditional: true,
              node: node,
              context: context,
              receiver: call,
              comments: comments_for(node),
              scope: scope,
              source: :parser
            )
            pins.push block_pin
            process_children region.update(closure: block_pin, compound_statement: block_pin)
          end
        end
      end
    end
  end
end
