# frozen_string_literal: true

module Solargraph
  class ComplexType
    class UniqueType
      # The RBS intersection type `A & B`: a value that is every conjunct
      # at once, so A & B <: A and A & B <: B.
      #
      # @see https://github.com/ruby/rbs/blob/master/docs/syntax.md#intersection-type
      class Intersection < UniqueType
        # Each conjunct is a full ComplexType, since RBS allows `(A | B) & C`.
        #
        # @return [Array<ComplexType>]
        attr_reader :conjuncts

        # @param conjuncts [Array<ComplexType>]
        def initialize conjuncts
          @conjuncts = conjuncts
          super(render(:tags), rooted: false)
        end

        # @return [String]
        def tag
          name
        end

        # @return [String]
        def rooted_tag
          @rooted_tag ||= render(:rooted_tags)
        end

        # @return [String]
        def to_rbs
          conjuncts.map(&:to_rbs).join(' & ')
        end

        def duck_type?
          false
        end

        def interface?
          false
        end

        def generic?
          conjuncts.any?(&:generic?)
        end

        def selfy?
          conjuncts.any?(&:selfy?)
        end

        def rooted?
          conjuncts.all?(&:rooted?)
        end

        def all_rooted?
          conjuncts.all?(&:all_rooted?)
        end

        # A & B <: C & D when A & B satisfies each of C and D; A & B <: C
        # when any one conjunct does.
        #
        # @param api_map [ApiMap]
        # @param expected [ComplexType, ComplexType::UniqueType]
        # @param situation [:method_call, :assignment, :return_type]
        # @param rules [Array<Symbol>]
        # @param variance [:invariant, :covariant, :contravariant]
        # @return [Boolean]
        def conforms_to? api_map, expected, situation, rules = [],
                         variance: erased_variance(situation)
          # Try union alternatives one at a time, so an intersection
          # alternative is compared as a whole rather than conjunct by conjunct.
          first = expected.items.first
          if expected.items.length > 1
            return true if expected.items.any? do |item|
              conforms_to?(api_map, item, situation, rules, variance: variance)
            end
          elsif first.is_a?(Intersection)
            return first.conjuncts.all? do |expected_conjunct|
              conforms_to?(api_map, expected_conjunct, situation, rules, variance: variance)
            end
          end

          conjuncts.any? do |conjunct|
            conjunct.conforms_to?(api_map, expected, situation, rules, variance: variance)
          end
        end

        # @param generics_to_resolve [Enumerable<String>]
        # @param context_type [ComplexType, UniqueType, nil]
        # @param resolved_generic_values [Hash{String => ComplexType, ComplexType::UniqueType}]
        # @return [Intersection]
        def resolve_generics_from_context generics_to_resolve, context_type, resolved_generic_values: {}
          Intersection.new(conjuncts.map do |conjunct|
            conjunct.resolve_generics_from_context(generics_to_resolve, context_type,
                                                   resolved_generic_values: resolved_generic_values)
          end)
        end

        # Transforms the named types inside each conjunct; the
        # intersection itself is not a named type, so it is not yielded.
        #
        # @param _new_name [String, nil]
        # @yieldparam t [UniqueType]
        # @yieldreturn [UniqueType]
        # @return [Intersection]
        def transform _new_name = nil, &transform_type
          Intersection.new(conjuncts.map { |conjunct| conjunct.transform(&transform_type) })
        end

        # @param api_map [ApiMap]
        # @param gates [Array<String>]
        # @return [Intersection]
        def qualify api_map, *gates
          Intersection.new(conjuncts.map { |conjunct| conjunct.qualify(api_map, *gates) })
        end

        # Only rootedness applies; an intersection has no name or
        # parameters of its own to replace.
        #
        # @param make_rooted [Boolean, nil]
        # @param _ignored [Hash{Symbol => String, Array<ComplexType>, nil}]
        # @return [Intersection]
        def recreate make_rooted: nil, **_ignored
          return self if make_rooted.nil?

          Intersection.new(conjuncts.map { |conjunct| conjunct.recreate(make_rooted: make_rooted) })
        end

        # @return [self]
        def erase_parameters
          self
        end

        # @param other [Object]
        def eql? other
          other.is_a?(Intersection) && conjuncts == other.conjuncts
        end

        def hash
          [self.class, conjuncts].hash
        end

        private

        # Brackets a multi-member conjunct, since `&` binds tighter than `,`.
        #
        # @param tags_method [:tags, :rooted_tags]
        # @return [String]
        def render tags_method
          conjuncts.map do |conjunct|
            tags = conjunct.send(tags_method)
            conjunct.items.length > 1 ? "[#{tags}]" : tags
          end.join(' & ')
        end
      end
    end
  end
end
