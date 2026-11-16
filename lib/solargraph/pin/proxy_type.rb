# frozen_string_literal: true

module Solargraph
  module Pin
    class ProxyType < Base
      attr_reader :generics

      # @param return_type [Type]
      # @param gates [Array<String>, nil] Namespaces to try while resolving non-rooted types
      # @param binder [ComplexType, ComplexType::UniqueType, nil]
      # @param gates [Array<String>, nil]
      # @param [Hash{Symbol => Object}] splat
      def initialize return_type: ComplexType::UNDEFINED, binder: nil, gates: nil, generics: [], **splat
        super(**splat)
        @gates = gates
        @return_type = return_type
        @binder = binder if binder
        @generics = generics
      end

      def context
        @return_type
      end

      # @param context [ComplexType, ComplexType::UniqueType] Used as context for this pin
      # @param closure [Pin::Closure, nil] Used as the closure for this pin;
      #   the root namespace if nil
      # @param binder [ComplexType, ComplexType::UniqueType, nil]
      # @return [ProxyType]
      # @param [Hash{Symbol => Object}] kwargs
      def self.anonymous context, closure: nil, binder: nil, **kwargs
        closure ||= Solargraph::Pin::Namespace.new(name: '', source: :proxy_type)
        ProxyType.new(
          closure: closure, return_type: context, binder: binder || context, **kwargs
        )
      end
    end
  end
end
