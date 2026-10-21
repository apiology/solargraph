# frozen_string_literal: true

module Solargraph
  module Parser
    module ParserGem
      module NodeProcessors
        class NamespaceNode < Parser::NodeProcessor::Base
          include ParserGem::NodeMethods

          def process
            name = unpack_name(node.children[0])
            comments = comments_for(node)

            superclass_name = type_from_node if node.type == :class

            loc = get_node_location(node)
            nspin = Solargraph::Pin::Namespace.new(
              type: node.type,
              location: loc,
              closure: region.closure,
              name: name,
              comments: comments,
              visibility: :public,
              gates: region.closure.gates.freeze,
              source: :parser
            )
            pins.push nspin
            if superclass_name
              pins.push Pin::Reference::Superclass.new(
                location: loc,
                closure: pins.last,
                name: superclass_name,
                generic_values: superclass_generic_values(nspin.generics),
                source: :parser
              )
            end
            process_children region.update(closure: nspin, visibility: :public)
          end

          private

          # Type arguments for a generic superclass in inline RBS syntax, e.g.,
          # `class Foo < Array #[String]`. Only recognized where RBS defines
          # it: directly after the superclass, on the same line, with no space
          # between `#` and `[`. Anything else is an ordinary comment.
          #
          # @return [String, nil]
          def parameters_from_inline_rbs
            superclass = node.children[1]
            return unless superclass

            source = region.source.code
            pos = get_node_end_position(superclass)
            offset = Position.line_char_to_offset(source, pos.line, pos.character)
            eol = source.index("\n", offset) || source.length
            match = source[offset...eol].to_s.match(/\A\s*#\[([^\]]*)\]/)
            return unless match

            code = match[1].strip
            return if code.empty?

            code
          end

          # Type arguments for the superclass, with any names declared by
          # the class's own `@generic` tags marked as generic parameters,
          # e.g., `generic<K>` for `class Foo < Hash #[K, V]`.
          #
          # @param generics [Array<String>]
          # @return [Array<String>]
          def superclass_generic_values generics
            code = parameters_from_inline_rbs
            return [] unless code

            type = ComplexType.try_parse("#{type_from_node}<#{code}>")
            type.all_params.map do |param|
              param.transform do |t|
                next t unless generics.include?(t.name) && t.all_params.empty?

                ComplexType.parse("#{ComplexType::GENERIC_TAG_NAME}<#{t.name}>").items.first
              end.to_s
            end
          end

          def type_from_node
            unpack_name(node.children[1]) if node.children[1]&.type == :const
          end
        end
      end
    end
  end
end
