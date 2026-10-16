# frozen_string_literal: true

module Solargraph
  class Source
    class Chain
      class InstanceVariable < Link
        # @param word [String]
        # @param node [Parser::AST::Node, nil] The node representing the variable
        # @param location [Location, nil] The location of the variable reference in the source
        def initialize word, node, location
          super(word)
          @node = node
          @location = location
        end

        def resolve api_map, name_pin, locals
          ivars = api_map.get_instance_variable_pins(name_pin.context.namespace, name_pin.context.scope).select do |p|
            p.name == word
          end
          # `@x = value` evaluates to value, which this assignment's own
          # pin types; earlier assignments and narrowings don't apply
          own = ivars.select { |p| assignment_with_value? && p.location == location }
          return own unless own.empty?

          out = api_map.var_at_location(ivars, word, name_pin, location)
          [out].compact
        end

        private

        # @return [Location, nil]
        attr_reader :location

        # True for `@x = value`; false for a read, or for the bare
        # target of `@x ||= value`, which names the previous value
        #
        # @return [Boolean]
        def assignment_with_value?
          node = @node
          return false if node.nil?

          node.type == :ivasgn && node.children.length == 2
        end
      end
    end
  end
end
