# frozen_string_literal: true

module Solargraph
  class ComplexType
    # Checks whether a type can be used in a given situation
    class Conformance
      # @param api_map [ApiMap]
      # @param inferred [ComplexType::UniqueType]
      # @param expected [ComplexType::UniqueType]
      # @param situation [:method_call, :return_type]
      # @param rules [Array<:allow_subtype_skew, :allow_empty_params, :allow_reverse_match,
      #   :allow_any_match, :allow_undefined, :allow_unresolved_generic,
      #   :allow_unmatched_interface>]
      # @param variance [:invariant, :covariant, :contravariant]
      def initialize api_map, inferred, expected,
                     situation = :method_call, rules = [],
                     variance: inferred.erased_variance(situation)
        @api_map = api_map
        @inferred = inferred
        @expected = expected
        @situation = situation
        @rules = rules
        @variance = variance
        # :nocov:
        unless expected.is_a?(UniqueType)
          # @sg-ignore This should never happen and the typechecker is angry about it
          raise "Expected type must be a UniqueType, got #{expected.class} in #{expected.inspect}"
        end
        # :nocov:
        return if inferred.is_a?(UniqueType)
        # :nocov:
        # @sg-ignore This should never happen and the typechecker is angry about it
        raise "Inferred type must be a UniqueType, got #{inferred.class} in #{inferred.inspect}"
        # :nocov:
      end

      def conforms_to_unique_type?
        unless expected.is_a?(UniqueType)
          # :nocov:
          raise "Expected type must be a UniqueType, got #{expected.class} in #{expected.inspect}"
          # :nocov:
        end

        return true if ignore_interface?
        return true if conforms_via_reverse_match?

        downcast_inferred = inferred.downcast_to_literal_if_possible
        downcast_expected = expected.downcast_to_literal_if_possible
        if (downcast_inferred.name != inferred.name) || (downcast_expected.name != expected.name)
          return with_new_types(downcast_inferred, downcast_expected).conforms_to_unique_type?
        end

        if rules.include?(:allow_subtype_skew) && !expected.all_params.empty?
          # parameters are not considered in this case
          return with_new_types(inferred, expected.erase_parameters).conforms_to_unique_type?
        end

        return with_new_types(inferred.erase_parameters, expected).conforms_to_unique_type? if only_inferred_parameters?

        return conforms_via_stripped_expected_parameters? if can_strip_expected_parameters?

        return true if inferred == expected

        return false unless erased_type_conforms?

        # A type with 2+ ordered generic params - a hash-shaped type
        # (parameters_type == :hash; Hash[K, V] is the only
        # stdlib/RBS example, but the YARD `{K => V}` tag syntax
        # admits any class name) always has 2 (key_types, subtypes),
        # and an ordinary `<A, B, ...>`-generic type
        # (parameters_type == :list) can have any number - may
        # satisfy a lower-arity Enumerable/_Each ancestor
        # structurally: #each yields all of its params together as
        # a tuple, so the type includes Enumerable[Array[K, V]] (or
        # Array[A, B, ...]), not Enumerable[V] (or Enumerable[A]).
        # Compare against that tuple shape instead of the raw
        # per-param types once erased_type_conforms? has already
        # established inferred <: expected via inheritance.
        return with_new_types(pair_shaped_as_pairs, expected).conforms_to_unique_type? if pair_shaped_viewed_as_pairs?

        return true if inferred.all_params.empty? && rules.include?(:allow_empty_params)

        # at this point we know the erased type is fine - time to look at parameters

        # there's an implicit 'any' on the expectation parameters
        # if there are none specified
        return true if expected.all_params.empty?

        return false unless key_types_conform?

        subtypes_conform?
      end

      private

      def only_inferred_parameters?
        !expected.parameters? && inferred.parameters?
      end

      def conforms_via_stripped_expected_parameters?
        with_new_types(inferred, expected.erase_parameters).conforms_to_unique_type?
      end

      def ignore_interface?
        (expected.any?(&:interface?) && rules.include?(:allow_unmatched_interface)) ||
          (inferred.interface? && rules.include?(:allow_unmatched_interface))
      end

      def can_strip_expected_parameters?
        expected.parameters? && !inferred.parameters? && rules.include?(:allow_empty_params)
      end

      def conforms_via_reverse_match?
        return false unless rules.include? :allow_reverse_match

        expected.conforms_to?(api_map, inferred, situation,
                              rules - [:allow_reverse_match],
                              variance: variance)
      end

      def erased_type_conforms?
        case variance
        when :invariant
          return false unless inferred.name == expected.name
        when :covariant
          # covariant: we can pass in a more specific type
          # we contain the expected mix-in, or we have a more specific type
          return false unless api_map.type_include?(inferred.name, expected.name) ||
                              api_map.super_and_sub?(expected.name, inferred.name) ||
                              inferred.name == expected.name
        when :contravariant
          # contravariant: we can pass in a more general type
          # we contain the expected mix-in, or we have a more general type
          return false unless api_map.type_include?(inferred.name, expected.name) ||
                              api_map.super_and_sub?(inferred.name, expected.name) ||
                              inferred.name == expected.name
        else
          # :nocov:
          raise "Unknown variance: #{variance.inspect}"
          # :nocov:
        end
        true
      end

      # @return [Boolean] true if `inferred` has 2+ ordered generic
      #   params (a hash-shaped type's key/value types, e.g.
      #   `Hash{K => V}`, or a `<A, B, ...>`-generic type's ordered
      #   params) being checked against an expectation of a
      #   different arity (e.g. a 1-arity Enumerable), so its
      #   params need to be viewed as a single tuple - not compared
      #   one-for-one - to conform
      def pair_shaped_viewed_as_pairs?
        return false unless inferred.all_params.size >= 2

        return expected.parameters_type != :hash if inferred.parameters_type == :hash

        inferred.parameters_type == :list && inferred.all_params.size != expected.all_params.size
      end

      # @return [UniqueType] `inferred` reshaped as `expected`'s name
      #   parametrized with the tuple its params form when yielded
      #   together - [key, value] for a hash-shaped type, or its
      #   ordered params for a `<A, B, ...>`-generic type
      def pair_shaped_as_pairs
        ordered_params = if inferred.parameters_type == :hash
                           [ComplexType.new(inferred.key_types), ComplexType.new(inferred.subtypes)]
                         else
                           inferred.all_params
                         end
        pair = UniqueType.new('Array', [], ordered_params, rooted: true, parameters_type: :fixed)
        UniqueType.new(expected.name, [], [pair], rooted: inferred.rooted?, parameters_type: :list)
      end

      def key_types_conform?
        return true if expected.key_types.empty?

        return false if inferred.key_types.empty?

        unless ComplexType.new(inferred.key_types).conforms_to?(api_map,
                                                                ComplexType.new(expected.key_types),
                                                                situation,
                                                                rules,
                                                                variance: inferred.parameter_variance(situation))
          return false
        end

        true
      end

      def subtypes_conform?
        return true if expected.subtypes.empty?

        return true if expected.subtypes.any?(&:undefined?) && rules.include?(:allow_undefined)

        return true if inferred.subtypes.any?(&:undefined?) && rules.include?(:allow_undefined)

        return true if inferred.subtypes.all?(&:generic?) && rules.include?(:allow_unresolved_generic)

        return true if expected.subtypes.all?(&:generic?) && rules.include?(:allow_unresolved_generic)

        return false if inferred.subtypes.empty?

        ComplexType.new(inferred.subtypes).conforms_to?(api_map,
                                                        ComplexType.new(expected.subtypes),
                                                        situation,
                                                        rules,
                                                        variance: inferred.parameter_variance(situation))
      end

      # @return [self]
      # @param inferred [ComplexType::UniqueType]
      # @param expected [ComplexType::UniqueType]
      def with_new_types inferred, expected
        self.class.new(api_map, inferred, expected, situation, rules, variance: variance)
      end

      attr_reader :api_map, :inferred, :expected, :situation, :rules, :variance
    end
  end
end
