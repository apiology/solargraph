# frozen_string_literal: true

module Solargraph
  class ComplexType
    class UniqueType
      # A single unique type representing the intersection of two or
      # more conjunct types, e.g., the RBS type `A & B`.
      #
      # Unlike ComplexType's comma-separated items (a union, where any
      # one member describes the value), every conjunct must describe
      # the value independently, so the subtyping rules are a union's
      # mirror image: A & B <: A and A & B <: B (<: means "is a
      # subtype of"), but a value satisfies A & B only if it satisfies
      # every conjunct.
      #
      #   A & B <: A
      #   A & B <: B
      #
      # i.e., a value typed as the intersection can be used wherever
      # *any* conjunct is expected, but a value can only be used
      # where the intersection itself is expected if it satisfies
      # *every* conjunct.
      #
      # Each conjunct is a full ComplexType, not a plain UniqueType -
      # the same way UniqueType#subtypes and #key_types already hold
      # ComplexTypes rather than UniqueTypes. RBS itself allows a
      # union as one member of an intersection (`(A | B) & C`), so a
      # conjunct needs to be able to represent more than one
      # alternative; a single type is just the common case of a
      # one-item ComplexType. This also means a conjunct can itself be
      # (or contain) another Intersection, since Intersection is a
      # UniqueType and ComplexType already holds UniqueTypes.
      #
      # `A & B` is parsed the same way from plain YARD type tags
      # (`@param`, `@return`, `@type`, etc.) as it is from inline RBS
      # signatures, since both funnel through ComplexType.parse. YARD
      # itself has no official intersection type syntax yet; `&` is
      # Solargraph's extension pending upstream guidance.
      #
      # @see https://en.wikipedia.org/wiki/Intersection_type
      # @see https://github.com/ruby/rbs/blob/master/docs/syntax.md#intersection-type
      # @see https://github.com/lsegal/yard/issues/1644
      class Intersection < UniqueType
        # @return [Array<ComplexType>]
        attr_reader :conjuncts

        # @param conjuncts [Array<ComplexType>]
        def initialize conjuncts
          @conjuncts = conjuncts
          super(intersection_tag(:tags), rooted: true)
        end

        # @return [String]
        def tag
          @tag ||= intersection_tag(:tags)
        end

        # @return [String]
        def rooted_tag
          @rooted_tag ||= intersection_tag(:rooted_tags)
        end

        # @return [String]
        def to_rbs
          conjuncts.map(&:to_rbs).join(' & ')
        end

        # @return [String]
        def namespace
          conjuncts.fetch(0).namespace
        end

        # @return [::Symbol]
        def scope
          conjuncts.fetch(0).scope
        end

        def generic?
          conjuncts.any?(&:generic?)
        end

        def rooted?
          conjuncts.all?(&:rooted?)
        end

        def all_rooted?
          conjuncts.all?(&:all_rooted?)
        end

        def duck_type?
          false
        end

        def interface?
          false
        end

        # @yieldparam [UniqueType]
        # @return [void]
        # @overload each_unique_type()
        #   @return [Enumerator<UniqueType>]
        def each_unique_type &block
          return enum_for(__method__) unless block_given?
          conjuncts.each { |conjunct| conjunct.each_unique_type(&block) }
        end

        # An intersection can be assigned wherever any one of its
        # conjuncts would be accepted (A & B <: A, A & B <: B). Each
        # conjunct is checked as a full ComplexType, so a conjunct
        # that's itself a union (from `(A | B) & C`) gets real union
        # semantics (every member of that union must conform).
        #
        # When expected is *also* an intersection, that simple "any
        # one conjunct" rule breaks down: a single one of our
        # conjuncts, checked alone, would have to satisfy every
        # conjunct expected of it - which fails whenever our conjuncts
        # don't already relate to each other, even when checking an
        # intersection against an identical copy of itself. The
        # correct rule for A & B <: C & D is that every conjunct of
        # the expected side must be satisfied by *some* conjunct of
        # this one (not necessarily the same one each time), so that
        # case is handled separately below.
        #
        # A union on the expected side is tried one alternative at a
        # time first, so that an intersection buried in a union is
        # still compared as an intersection. Checking the conjuncts
        # against the whole union instead asks a single conjunct to
        # carry the match on its own, which `A & false` cannot do
        # against a union that contains `A & false` itself.
        #
        # @param api_map [ApiMap]
        # @param expected [ComplexType, ComplexType::UniqueType]
        # @param situation [:method_call, :assignment, :return_type]
        # @param rules [Array<:allow_subtype_skew, :allow_empty_params, :allow_reverse_match, :allow_any_match, :allow_undefined, :allow_unresolved_generic>]
        # @param variance [:invariant, :covariant, :contravariant]
        # @return [Boolean]
        def conforms_to? api_map, expected, situation, rules = [],
                         variance: erased_variance(situation)
          return true if any_union_alternative_conforms?(api_map, expected, situation, rules, variance)

          expected_intersection = sole_intersection(expected)
          if expected_intersection
            return conforms_to_record_subset?(api_map, expected_intersection, rules, variance) if situation == :assignment

            return expected_intersection.conjuncts.all? do |expected_conjunct|
              conjuncts.any? do |conjunct|
                conjunct.conforms_to?(api_map, expected_conjunct, situation, rules, variance: variance)
              end
            end
          end
          conjuncts.any? do |conjunct|
            conjunct.conforms_to?(api_map, expected, situation, rules, variance: variance)
          end
        end

        # Every conjunct resolves against the same context, sharing
        # resolved_generic_values - resolved left to right, so an
        # earlier conjunct won't see a generic only a later one binds.
        #
        # @param generics_to_resolve [Enumerable<String>]
        # @param context_type [ComplexType, UniqueType, nil]
        # @param resolved_generic_values [Hash{String => ComplexType, UniqueType}]
        # @return [Intersection]
        def resolve_generics_from_context generics_to_resolve, context_type, resolved_generic_values: {}
          Intersection.new(conjuncts.map do |conjunct|
            conjunct.resolve_generics_from_context(generics_to_resolve, context_type,
                                                   resolved_generic_values: resolved_generic_values)
          end)
        end

        # Applies the transformation to each conjunct independently
        # and rebuilds the intersection from the results.
        #
        # new_name is not passed down to the conjuncts. An
        # intersection's own `name` is the synthetic `"A & B"` string
        # built in #initialize, not a namespace; giving that to each
        # conjunct renames `Hash{"a" => Float}` to
        # `Hash{"a" => Float} & Hash{"b" => Float}{"a" => Float}`,
        # which no longer parses. Each conjunct keeps its own name,
        # which is the only rename that means anything here.
        #
        # @param _new_name [String, nil] ignored - see above
        # @yieldparam t [UniqueType]
        # @yieldreturn [UniqueType]
        # @return [self]
        def transform _new_name = nil, &transform_type
          Intersection.new(conjuncts.map { |conjunct| conjunct.transform(&transform_type) })
        end

        # UniqueType#qualify walks key_types and subtypes; an
        # intersection holds neither, so it qualifies its conjuncts.
        #
        # @param api_map [ApiMap]
        # @param gates [Array<String>]
        # @return [Intersection]
        def qualify api_map, *gates
          Intersection.new(conjuncts.map { |conjunct| conjunct.qualify(api_map, *gates) })
        end

        # @return [self]
        def erase_parameters
          self
        end

        private

        # Renders conjuncts as a tag, bracketing multi-item ones since
        # `&` binds tighter than `,`/`|` (`[A|B] & C`, not `A, B & C`).
        #
        # @param tags_method [:tags, :rooted_tags]
        # @return [String]
        def intersection_tag tags_method
          conjuncts.map do |conjunct|
            tags = conjunct.send(tags_method)
            conjunct.items.length > 1 ? "[#{tags}]" : tags
          end.join(' & ')
        end

        # An assignment's declared `A & B & C` (e.g. `# @type [Hash{:k1
        # => V1} & Hash{:k2 => V2} & Hash{:k3 => V3}]` on a local
        # variable) states the full eventual shape a Hash literal will
        # grow into via later `[]=`/`merge!` calls, not a set of keys
        # the initializer must already carry. So for each expected
        # conjunct that is itself a single-key Hash record: if this
        # intersection has no conjunct for that key yet, that's fine -
        # it isn't declared missing, just not populated yet. If it does
        # have one, that conjunct's value still has to conform.
        #
        # Any expected conjunct that isn't a single-key Hash record
        # falls back to the ordinary "some conjunct of ours satisfies
        # it" rule - this leniency is specific to the Hash-record
        # accretion pattern, not a general loosening of intersection
        # assignment.
        #
        # @param api_map [ApiMap]
        # @param expected_intersection [Intersection]
        # @param rules [Array<Symbol>]
        # @param variance [:invariant, :covariant, :contravariant]
        # @return [Boolean]
        def conforms_to_record_subset? api_map, expected_intersection, rules, variance
          expected_intersection.conjuncts.all? do |expected_conjunct|
            unless single_key_hash_record?(expected_conjunct)
              next conjuncts.any? do |conjunct|
                conjunct.conforms_to?(api_map, expected_conjunct, :assignment, rules, variance: variance)
              end
            end

            matching = conjuncts.select { |conjunct| same_hash_record_key?(conjunct, expected_conjunct) }
            next true if matching.empty?

            matching.any? do |conjunct|
              conjunct.conforms_to?(api_map, expected_conjunct, :assignment, rules, variance: variance)
            end
          end
        end

        # @param complex_type [ComplexType]
        # @return [Boolean]
        def single_key_hash_record? complex_type
          return false unless complex_type.is_a?(ComplexType) && complex_type.length == 1

          unique_type = complex_type.first
          unique_type.name == 'Hash' && unique_type.key_types.length == 1
        end

        # @param conjunct [ComplexType]
        # @param expected_conjunct [ComplexType]
        # @return [Boolean]
        def same_hash_record_key? conjunct, expected_conjunct
          return false unless single_key_hash_record?(conjunct)

          conjunct.first.key_types.first == expected_conjunct.first.key_types.first
        end

        # True when expected is a union and this intersection conforms
        # to one of its alternatives taken on its own.
        #
        # @param api_map [ApiMap]
        # @param expected [ComplexType, ComplexType::UniqueType]
        # @param situation [:method_call, :assignment, :return_type]
        # @param rules [Array<Symbol>]
        # @param variance [:invariant, :covariant, :contravariant]
        # @return [Boolean]
        def any_union_alternative_conforms? api_map, expected, situation, rules, variance
          return false unless expected.is_a?(ComplexType) && expected.length > 1

          expected.items.any? do |item|
            conforms_to?(api_map, ComplexType.new([item]), situation, rules, variance: variance)
          end
        end

        # Returns expected itself (or its one item) when it's an Intersection, else nil.
        #
        # @param expected [ComplexType, ComplexType::UniqueType]
        # @return [Intersection, nil]
        def sole_intersection expected
          return expected if expected.is_a?(Intersection)
          return expected.first if expected.is_a?(ComplexType) && expected.length == 1 && expected.first.is_a?(Intersection)
          nil
        end
      end
    end
  end
end
