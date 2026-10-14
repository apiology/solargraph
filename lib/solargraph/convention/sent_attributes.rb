# frozen_string_literal: true

module Solargraph
  module Convention
    # Maps attributes declared by sending +attr_reader+, +attr_writer+ or
    # +attr_accessor+ to an implicit receiver, self or a constant, e.g.:
    #
    #   send(:attr_reader, :name)                        # => #name
    #   Rails::Application.send(:attr_accessor, :importmap)
    #     # => Rails::Application#importmap, #importmap=
    #
    module SentAttributes
      # @return [Array<Symbol>]
      SEND_METHODS = %i[send public_send].freeze

      # @return [Array<Symbol>]
      ATTRIBUTE_METHODS = %i[attr_reader attr_writer attr_accessor].freeze

      module NodeProcessors
        class SendNode < Parser::NodeProcessor::Base
          # @return [Boolean] continue processing the next processor of the same node.
          def process
            kind = attribute_kind
            return true if kind.nil?

            closure = constant_closure
            if closure
              map_attributes kind, closure, :instance, :public
            else
              map_attributes kind, region.closure, region.scope || :instance, region.visibility
            end
            true
          end

          private

          # The attribute method sent, if the receiver is implicit, self or
          # a constant.
          #
          # @return [Symbol, nil]
          def attribute_kind
            return unless SEND_METHODS.include?(node.children[1])
            receiver = node.children[0]
            return unless receiver.nil? || (receiver.is_a?(AST::Node) && %i[self const].include?(receiver.type))
            sym = node.children[2]
            return unless sym.is_a?(AST::Node)
            return unless sym.type == :sym
            kind = sym.children[0]
            kind if kind.is_a?(Symbol) && ATTRIBUTE_METHODS.include?(kind)
          end

          # The namespace of a constant receiver.
          #
          # @return [Pin::Namespace, nil]
          def constant_closure
            receiver = node.children[0]
            return unless receiver.is_a?(AST::Node)
            return unless receiver.type == :const
            Pin::Namespace.new(location: get_node_location(receiver),
                               name: Parser::NodeMethods.unpack_name(receiver), source: :parser)
          end

          # @param kind [Symbol] :attr_reader, :attr_writer or :attr_accessor
          # @param closure [Pin::Closure]
          # @param scope [Symbol] :class or :instance
          # @param visibility [Symbol]
          # @return [void]
          def map_attributes kind, closure, scope, visibility
            (node.children[3..] || []).each do |arg|
              next unless arg.is_a?(AST::Node) && %i[sym str].include?(arg.type)
              name = arg.children[0].to_s
              pins.push attribute_pin(name, closure, scope, visibility) unless kind == :attr_writer
              next if kind == :attr_reader
              writer = attribute_pin("#{name}=", closure, scope, visibility)
              pins.push writer
              writer.parameters.push Pin::Parameter.new(name: 'value', decl: :arg, closure: writer, source: :parser)
              type = writer.return_type
              next if type.nil? || type.undefined?
              writer.docstring.add_tag YARD::Tags::Tag.new(:param, '', type.items.map(&:rooted_tags), 'value')
            end
          end

          # @param name [String]
          # @param closure [Pin::Closure]
          # @param scope [Symbol] :class or :instance
          # @param visibility [Symbol]
          # @return [Pin::Method]
          def attribute_pin name, closure, scope, visibility
            Pin::Method.new(
              location: get_node_location(node),
              closure: closure,
              name: name,
              comments: comments_for(node),
              scope: scope,
              visibility: visibility,
              attribute: true,
              source: :parser
            )
          end
        end
      end
    end
  end
end
