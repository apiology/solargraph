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
      # Each conjunct is a full ComplexType, not a plain UniqueType, as
      # RBS allows a union as one member of an intersection
      # (`(A | B) & C`) - and so a conjunct may itself be an
      # Intersection.
      #
      # `A & B` parses the same from plain YARD type tags as from
      # inline RBS signatures, since both funnel through
      # ComplexType.parse. YARD has no official intersection syntax
      # yet; `&` is Solargraph's extension pending upstream guidance.
      #
      # @see https://en.wikipedia.org/wiki/Intersection_type
      # @see https://github.com/ruby/rbs/blob/master/docs/syntax.md#intersection-type
      # @see https://github.com/lsegal/yard/issues/1644
      class Intersection
        include Equality

        # @return [Array<ComplexType>]
        attr_reader :conjuncts

        # @param conjuncts [Array<ComplexType>]
        def initialize conjuncts
          @conjuncts = conjuncts
        end

        # @return [String]
        def tags
          @tags ||= intersection_tag(:tags)
        end

        # @return [String]
        def rooted_tags
          @rooted_tags ||= intersection_tag(:rooted_tags)
        end

        # @return [String]
        def to_s
          tags
        end

        # @return [String]
        def to_rbs
          conjuncts.map(&:to_rbs).join(' & ')
        end

        # The whole intersection, as #tags renders it: there is no
        # single named member to report.
        #
        # @return [String]
        def tag
          tags
        end

        # @return [String]
        def rooted_tag
          rooted_tags
        end

        # @return [String]
        def desc
          rooted_tags
        end

        # An intersection is never itself a duck type; a duck-typed
        # conjunct is checked through #provides_duck_method?.
        #
        # @return [Boolean]
        def duck_type?
          false
        end

        # Whether any conjunct mentions a type variable.
        #
        # @return [Boolean]
        def generic?
          conjuncts.any?(&:generic?)
        end

        # @return [Boolean]
        def rooted?
          conjuncts.all?(&:rooted?)
        end

        # One literal conjunct bounds the value to that literal.
        #
        # @return [Boolean]
        def literal?
          conjuncts.any?(&:literal?)
        end

        # @return [Intersection]
        def downcast_to_literal_if_possible
          Intersection.new(conjuncts.map(&:downcast_to_literal_if_possible))
        end

        # @return [Intersection]
        def simplify_literals
          # @sg-ignore Symbol#to_proc over a [self] return type infers Array<Array<ComplexType>>
          Intersection.new(conjuncts.map(&:simplify_literals))
        end

        # @return [Intersection]
        def force_rooted
          # @sg-ignore Symbol#to_proc over a [self] return type infers Array<Array<ComplexType>>
          Intersection.new(conjuncts.map(&:force_rooted))
        end

        # @param named_types [Hash{String => ComplexType, UniqueType}]
        # @return [Intersection]
        def expand named_types
          Intersection.new(conjuncts.map { |conjunct| conjunct.expand(named_types) })
        end

        # @param dst [ComplexType]
        # @return [Intersection]
        def self_to_type dst
          Intersection.new(conjuncts.map { |conjunct| conjunct.self_to_type(dst) })
        end

        # A conjunct that is only nil leaves nothing once nil is
        # dropped; otherwise nil drops out of each conjunct, so
        # (A | nil) & B without nil is A & B.
        #
        # @return [Intersection, UniqueType]
        def without_nil
          return UniqueType::UNDEFINED if conjuncts.any? { |conjunct| conjunct.items.all?(&:nil_type?) }

          Intersection.new(conjuncts.map(&:without_nil))
        end

        # @param exclude_types [ComplexType, nil]
        # @param api_map [ApiMap]
        # @return [ComplexType, self]
        def exclude exclude_types, api_map
          return self if exclude_types.nil?

          types = items - exclude_types.items
          types = [UniqueType::UNDEFINED] if types.empty?
          ComplexType.new(types)
        end

        # @return [Boolean]
        def any_generic?
          conjuncts.any?(&:any_generic?)
        end

        def all_rooted?
          conjuncts.all?(&:all_rooted?)
        end

        # A void conjunct says nothing about the value and drops out,
        # so the intersection is void only once none is left.
        #
        # @return [Boolean]
        def void?
          conjuncts.all?(&:void?)
        end

        # An undefined conjunct adds no restriction and drops out, so
        # the intersection is undefined only once none is left.
        #
        # @return [Boolean]
        def undefined?
          conjuncts.all?(&:undefined?)
        end

        # A & nil is a subtype of nil, so every value of it is nil: one
        # nil conjunct makes the whole intersection the nil type.
        #
        # @return [Boolean]
        def nil_type?
          conjuncts.any?(&:nil_type?)
        end

        # nil satisfies the intersection only by satisfying every
        # conjunct, so Foo & nil admits nothing at all.
        #
        # @return [Boolean]
        def nullable?
          conjuncts.all?(&:nullable?)
        end

        # Whether self appears anywhere in the type, so a receiver has
        # to be substituted before use - one conjunct is enough.
        #
        # @return [Boolean]
        def selfy?
          conjuncts.any?(&:selfy?)
        end

        # An intersection is one member of a union, as a UniqueType is.
        #
        # @return [Array<Intersection>]
        def items
          [self]
        end

        # @return [Array<Intersection>]
        def to_a
          [self]
        end

        # @yieldparam t [Intersection]
        # @return [Enumerable<Intersection>]
        def each(&)
          [self].each(&)
        end

        # @yieldparam [Intersection]
        # @return [void]
        # @overload each_unique_type()
        #   @return [Enumerator<Intersection>]
        def each_unique_type(&)
          return enum_for(__method__) unless block_given?
          yield self
        end

        # @yieldparam t [Intersection]
        # @return [Array]
        def map
          [yield(self)]
        end

        # @yieldreturn [Boolean]
        def all? &block
          block.yield self
        end

        # @yieldreturn [Boolean]
        def any? &block
          block.yield self
        end

        # @return [Boolean]
        def defined?
          !undefined?
        end

        # @param api_map [ApiMap]
        # @param gates [Array<String>]
        # @return [Intersection]
        def qualify api_map, *gates
          Intersection.new(conjuncts.map { |conjunct| conjunct.qualify(api_map, *gates) })
        end

        # @param other [Object]
        # @return [Boolean]
        def eql? other
          # @sg-ignore flow sensitive typing should support .class == .class
          self.class == other.class && sorted_conjuncts == other.sorted_conjuncts
        end

        # @return [Integer]
        def hash
          [self.class, sorted_conjuncts].hash
        end

        # Substituting one type for another where this one is expected
        # is safe only where it is safe for every conjunct, so the
        # variance is whatever the conjuncts agree on - and invariant
        # when they disagree, since no one direction then holds for all.
        #
        # @param situation [:method_call, :return_type, :assignment]
        # @return [:invariant, :covariant, :contravariant]
        def erased_variance situation = :method_call
          variances = conjuncts.map { |conjunct| conjunct.erased_variance(situation) }.uniq
          variances.length == 1 ? variances.fetch(0) : :invariant
        end

        # An intersection can be assigned wherever any one of its
        # conjuncts would be accepted (A & B <: A, A & B <: B). Each
        # conjunct is checked as a full ComplexType, so a conjunct
        # that's itself a union (from `(A | B) & C`) gets real union
        # semantics (every member of that union must conform).
        #
        # When expected is *also* an intersection, the rule instead is
        # that every conjunct of the expected side must be satisfied by
        # *some* conjunct of this one, not necessarily the same one each
        # time - handled separately below.
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
          expected.satisfied_by?(self, api_map, situation, rules, variance: variance)
        end

        # Whether this intersection conforms to a single named
        # expectation: one conjunct carrying it is enough, since the
        # value is all of them at once.
        #
        # @param expected [ComplexType::UniqueType]
        # @param api_map [ApiMap]
        # @param situation [:method_call, :assignment, :return_type]
        # @param rules [Array<Symbol>]
        # @param variance [:invariant, :covariant, :contravariant]
        # @return [Boolean]
        def conforms_to_unique? expected, api_map, situation, rules = [],
                                variance: erased_variance(situation)
          conjuncts.any? do |conjunct|
            conjunct.conforms_to_unique?(expected, api_map, situation, rules, variance: variance)
          end
        end

        # What an inferred type must do to satisfy this intersection:
        # conform to every conjunct, since A & B <: A and A & B <: B.
        #
        # @param inferred [ComplexType, ComplexType::UniqueType, Intersection]
        # @param api_map [ApiMap]
        # @param situation [:method_call, :assignment, :return_type]
        # @param rules [Array<Symbol>]
        # @param variance [:invariant, :covariant, :contravariant]
        # @return [Boolean]
        def satisfied_by? inferred, api_map, situation, rules = [],
                          variance: inferred.erased_variance(situation)
          conjuncts.all? do |conjunct|
            inferred.conforms_to?(api_map, conjunct, situation, rules, variance: variance)
          end
        end

        # The methods reachable on a value of this intersection: the value
        # is every conjunct at once, so it offers whatever any conjunct
        # offers.
        #
        # @param api_map [ApiMap]
        # @param context [String] Fully qualified namespace the type is referenced from
        # @param internal [Boolean] True to include private methods
        # @return [Array<Pin::Base>]
        def candidate_methods_from api_map, context, internal
          conjuncts.flat_map { |conjunct| conjunct.candidate_methods_from(api_map, context, internal) }
                   .uniq
        end

        # Whether any conjunct provides +quack+: the value is all of them
        # at once, so one is enough.
        #
        # @param api_map [ApiMap]
        # @param quack [String]
        # @return [Boolean]
        def provides_duck_method? api_map, quack
          conjuncts.any? { |conjunct| conjunct.provides_duck_method?(api_map, quack) }
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

        # Each conjunct probes the same definitions and receiver, as in
        # #resolve_generics_from_context above.
        #
        # @param definitions [Pin::Namespace, Pin::Method] The module/class/method which uses generic types
        # @param context_type [ComplexType] The receiver type
        # @return [Intersection]
        def resolve_generics definitions, context_type
          Intersection.new(conjuncts.map { |conjunct| conjunct.resolve_generics(definitions, context_type) })
        end

        # Applies the transformation to each conjunct independently
        # and rebuilds the intersection from the results.
        #
        # An intersection has no name of its own to replace, so
        # new_name is ignored and each conjunct keeps its own.
        #
        # @param _new_name [String, nil] ignored - see above
        # @yieldparam t [UniqueType]
        # @yieldreturn [UniqueType]
        # @return [self]
        def transform _new_name = nil, &transform_type
          Intersection.new(conjuncts.map { |conjunct| conjunct.transform(&transform_type) })
        end

        # @param api_map [ApiMap]
        # @param gates [Array<String>]
        # @return [Intersection]
        def unalias_and_qualify api_map, *gates
          Intersection.new(conjuncts.map { |conjunct| conjunct.unalias_and_qualify(api_map, *gates) })
        end

        # @return [self]
        def erase_parameters
          self
        end

        # Reduction distributes over conjuncts: Class<A> & Class<B>
        # describes a value that is both an A and a B.
        #
        # @return [ComplexType]
        def reduce_class_type
          ComplexType.new([Intersection.new(conjuncts.map(&:reduce_class_type))])
        end

        # Unwrapping distributes over conjuncts: a value that is both
        # an Object<A, B> and a C is both an A-or-B and a C.
        #
        # @return [ComplexType]
        def reduce_object
          ComplexType.new([Intersection.new(conjuncts.map(&:reduce_object))])
        end

        # Erasure drops parameters conjunct by conjunct, so this holds
        # only against another intersection lining up one for one. A
        # named type is not this type with its parameters dropped.
        #
        # @param other [ComplexType, ComplexType::UniqueType, Intersection]
        # @return [Boolean]
        def erased_version_of? other
          return false unless other.is_a?(Intersection)
          return false unless conjuncts.length == other.conjuncts.length

          # @sg-ignore https://github.com/castwide/solargraph/pull/1223
          conjuncts.zip(other.conjuncts).all? { |mine, theirs| mine.erased_version_of?(theirs) }
        end

        protected

        # The conjunct set #eql? and #hash already answer from, wrapped so
        # Equality#freeze freezes the set and not each conjunct: freezing
        # a conjunct ComplexType freezes the ComplexType class itself,
        # since its own equality_fields lead with self.class.
        #
        # @return [Array<Array<ComplexType>>]
        def equality_fields
          [sorted_conjuncts]
        end

        # Conjunct order is not part of the type. rooted_tags keys the
        # sort rather than tag, which reports only a union conjunct's
        # first member and drops the :: from a rooted one.
        #
        # @return [Array<ComplexType>]
        def sorted_conjuncts
          conjuncts.sort_by(&:rooted_tags)
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
      end
    end
  end
end
