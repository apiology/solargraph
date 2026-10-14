# frozen_string_literal: true

module Solargraph
  module Pin
    class Reference
      # An include, extend or prepend whose argument is an expression rather
      # than a constant, e.g. `include registry.helpers`. ApiMap infers the
      # expression once the store is built and maps the module it returns.
      #
      class DynamicMixin < Reference
        # @return [Class<Reference::Include>, Class<Reference::Extend>, Class<Reference::Prepend>]
        attr_reader :mixin

        # @return [::Parser::AST::Node]
        attr_reader :node

        # @return [Array<Pin::LocalVariable>] locals visible at the call
        attr_reader :locals

        # @return [Pin::Closure, nil] the namespace receiving the module, when
        #   it is not the closure the expression is evaluated in
        attr_reader :target

        # @param mixin [Class<Reference::Include>, Class<Reference::Extend>, Class<Reference::Prepend>]
        # @param node [::Parser::AST::Node]
        # @param locals [Array<Pin::LocalVariable>]
        # @param target [Pin::Closure, nil]
        # @param splat [Hash{Symbol => Object}]
        def initialize mixin:, node:, locals: [], target: nil, **splat
          super(**splat)
          @mixin = mixin
          @node = node
          @locals = locals
          @target = target
        end
      end
    end
  end
end
