# frozen_string_literal: true

module Solargraph
  class Source
    class Chain
      class Hash < Literal
        # @param type [String]
        # @param node [Parser::AST::Node]
        # @param splatted [Boolean]
        def initialize type, node, splatted = false
          super(type, node)
          @splatted = splatted
        end

        def word
          @word ||= "<#{@type}>"
        end

        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base]
        # @param locals [::Array<Pin::Base>]
        # @param _receiver_path [::Array<String>, nil]
        def resolve api_map, name_pin, locals, _receiver_path = nil
          [Pin::ProxyType.anonymous(@complex_type, source: :chain)]
        end

        def splatted?
          @splatted
        end

        protected

        def equality_fields
          super + [@splatted]
        end
      end
    end
  end
end
