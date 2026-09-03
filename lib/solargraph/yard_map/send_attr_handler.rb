# frozen_string_literal: true

# YARD handler for defining attr_accessor/attr_reader/attr_writer on an
# EXTERNAL constant via `send`, e.g.:
#
#   Rails::Application.send(:attr_accessor, :importmap)
#
# a common plain-Ruby idiom (used well beyond Rails/ActiveSupport) for
# adding accessors to a class a gem doesn't own, since `attr_accessor`
# itself is private. Neither plain YARD nor `yard-activesupport-concern`
# recognizes it. Loaded via `yardoc -e` from Solargraph::Yardoc.cache,
# alongside `--plugin solargraph`.
module YARD
  module Handlers
    module Ruby
      class SendAttrHandler < YARD::Handlers::Ruby::Base
        ATTR_METHODS = %i[attr_accessor attr_reader attr_writer].freeze

        handles method_call(:send)

        process do
          receiver = statement.namespace
          next unless receiver

          params = statement.parameters(false).dup
          next if params.empty?

          attr_method = symbol_literal(params.shift)
          next unless ATTR_METHODS.include?(attr_method)

          target = YARD::CodeObjects::Proxy.new(namespace, receiver.source)
          read = attr_method != :attr_writer
          write = attr_method != :attr_reader

          validated_attribute_names(params).each do |name|
            define_attr_method(target, name) if read
            define_attr_method(target, "#{name}=", writer: true) if write
          end
        end

        private

        # @param target [YARD::CodeObjects::Base]
        # @param meth [String]
        # @param writer [Boolean]
        # @return [void]
        def define_attr_method target, meth, writer: false
          o = MethodObject.new(target, meth, :instance)
          if writer
            o.parameters = [['value', nil]]
            o.signature ||= "def #{meth}(value)"
          else
            o.signature ||= "def #{meth}"
          end
          o.source ||= "#{o.signature}\nend"
          register(o)
        end

        # @param node [YARD::Parser::Ruby::AstNode]
        # @return [Symbol, nil]
        def symbol_literal node
          return nil unless node.type == :symbol_literal
          node.jump(:ident, :op, :kw, :const).source.to_sym
        end

        # @param params [Array<YARD::Parser::Ruby::AstNode>]
        # @return [Array<String>]
        def validated_attribute_names params
          params.map do |obj|
            case obj.type
            when :symbol_literal
              obj.jump(:ident, :op, :kw, :const).source
            when :string_literal
              obj.jump(:string_content).source
            else
              raise YARD::Parser::UndocumentableError, obj.source
            end
          end
        end
      end
    end
  end
end
