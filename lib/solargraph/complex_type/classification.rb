# frozen_string_literal: true

module Solargraph
  class ComplexType
    # What the ApiMap knows about a single UniqueType: the namespace it
    # resolves to, whether values of it are objects or the class/module
    # object itself, whether that namespace is defined as a class or a
    # module, and how many values inhabit it.
    #
    # Resolving a type against the ApiMap costs a pin lookup, and more
    # than one rule needs the answer - so the lookup happens once here
    # and the rules read the result. Narrowing is the only caller
    # today; union simplification will want the same facts per arm,
    # which is why this is per-type rather than per-pair.
    class Classification
      # Types with exactly one value. Two of them describe the same
      # value only when they are the same type.
      #
      # Only `nil` reaches here in practice: qualification unaliases
      # `true` and `false` to `Boolean`, which has two values and no
      # namespace pin, so a `Boolean` is classified as if it were
      # unresolved. The other two names are listed because this
      # classifies whatever type it is handed, including types that
      # have not been through #qualify.
      SINGLETON_NAMES = %w[nil true false].freeze

      # @return [ComplexType::UniqueType]
      attr_reader :type

      # @param api_map [ApiMap]
      # @param type [ComplexType::UniqueType]
      def initialize api_map, type
        @api_map = api_map
        @type = type
      end

      # @return [String]
      def namespace
        type.namespace
      end

      # :instance for a value of the namespace, :class for the
      # class/module object itself (`Class<Foo>`, `Module<Bar>`).
      #
      # @return [::Symbol]
      def scope
        type.scope
      end

      # How the namespace is declared, which is not the same question
      # as #scope: `Module<Bar>` has an :instance-less :class scope and
      # a :module namespace kind.
      #
      # @return [:class, :module, nil] nil when the namespace has no pin
      def namespace_kind
        return @namespace_kind if defined?(@namespace_kind)

        # @type [Pin::Namespace, nil]
        pin = api_map.get_path_pins(namespace).find { |p| p.is_a?(Pin::Namespace) }
        @namespace_kind = pin&.type
      end

      # @return [Boolean]
      def module?
        namespace_kind == :module
      end

      # Whether values of this type are the class or module object
      # rather than an instance of it.
      #
      # @return [Boolean]
      def metatype?
        scope == :class
      end

      # Whether this names a module that another object could pick up
      # via `extend` - a module used as an instance type (`Mod`), not
      # the module object itself (`Module<Mod>`).
      #
      # @return [Boolean]
      def extendable_module?
        module? && !metatype?
      end

      # @return [Boolean]
      def singleton_valued?
        SINGLETON_NAMES.include?(type.name)
      end

      private

      # @return [ApiMap]
      attr_reader :api_map
    end
  end
end
