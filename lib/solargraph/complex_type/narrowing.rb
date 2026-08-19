# frozen_string_literal: true

module Solargraph
  class ComplexType
    # What a declared type reduces to once a runtime guard proves a
    # second type also holds. Conformance answers whether one type
    # satisfies another; this answers what the pair leaves behind.
    #
    # Narrowing is not the same thing as an intersection, and the two
    # are easy to conflate because one can produce the other. An
    # intersection is a *type*: `A & B` describes a value that is both.
    # Narrowing is an *operation* on a pair of types, and building an
    # intersection is only one of its five outcomes - the pair may also
    # collapse to whichever side is more specific, or be dropped
    # because nothing inhabits both, or be dropped because no relation
    # could be established. Asking "would `A & B` be a sensible type?"
    # in place of "what does this pair narrow to?" is what produced the
    # defect this class was extracted to fix: a module-valued metatype
    # was paired with `nil` because the namespace named a module, which
    # is a true fact about the intersection question and the wrong
    # question to be asking.
    #
    # There is no narrowing operator, and its absence is why narrowing
    # keeps looking like it should be `&`. `&` and `|` are type
    # constructors with surface syntax - a user writes them in an
    # annotation to describe a value. Narrowing has no syntax because
    # a user never writes it: they write `x.is_a?(Foo)`, `x.nil?`, or
    # `x || Foo`, and the inference engine derives a narrowed type from
    # the control flow around that expression. The inputs here are a
    # declared type and a fact deduced from a guard, not two types
    # someone wrote down side by side.
    #
    # RBS has no narrowing concept to follow. It is "a language to
    # describe the structure of Ruby programs" (its README), so it
    # specifies `A & B` and `A | B` as type constructors but says
    # nothing about refining a type from control flow - rbs 4.1.3
    # contains no occurrence of "narrowing", "flow-sensitive" or
    # "type guard" in its code, docs or signatures. Narrowing belongs
    # to whatever checker consumes RBS rather than to RBS, so the rules
    # below are Solargraph's own and are not constrained by an RBS
    # specification.
    #
    # The verdict is a Symbol rather than a Boolean because the caller
    # has four distinct things to do with the answer, and because :bot
    # and :incomparable are different claims. :bot is positive - the
    # rules proved no value inhabits both. :incomparable is an absence
    # - at least one side has no namespace pin, so no rule could
    # classify the pair at all. That happens either because the
    # namespace is genuinely unresolved or because the type is not a
    # namespace (`void`, `self`, `generic<T>`, and Solargraph's
    # synthetic `Boolean` all have no pin).
    #
    # Both drop the pair today, so nothing downstream can yet tell
    # them apart. They are still separate verdicts because only a
    # proved-empty pair could justify reducing to a bottom type, and
    # recording which pairs are provably empty is what will make that
    # reduction safe to switch on mechanically rather than re-derive.
    class Narrowing
      # @param api_map [ApiMap]
      # @param left [ComplexType::UniqueType] the declared type
      # @param right [ComplexType::UniqueType] the type the guard proved
      def initialize api_map, left, right
        @api_map = api_map
        @left = left
        @right = right
      end

      # @return [:left, :right, :intersect, :bot, :incomparable]
      def verdict
        # The declared type is tried first so that when the two
        # conform in both directions the user's annotation survives:
        # it carries rooting and type parameters that a guard-derived
        # type (a bare `Foo` from `is_a?`, or `nil, false` from a
        # truthiness split) does not.
        return :left if left.conforms_to?(api_map, right, :assignment)
        return :right if right.conforms_to?(api_map, left, :assignment)
        # Named for the type this pair should reduce to, which is not
        # the type it currently reduces to - the pair is dropped and
        # #narrow_with still falls back to UNDEFINED. The name is meant
        # to fail that search: it marks a placeholder rather than a
        # finished rule.
        #
        # It cannot be honoured on this branch. UniqueType#bot? does
        # not exist here - it arrives with
        # https://github.com/castwide/solargraph/pull/1277 - and while
        # ComplexType::BOT and ComplexType#bottom? are both already
        # defined, `bottom?` is `@items.all?(&:bot?)` and so raises
        # NoMethodError if anything calls it. Nothing does.
        #
        # Once #1277 lands, #narrow_with should return ComplexType::BOT
        # instead of UNDEFINED when every pair came back :bot. That
        # needs the loop to record its verdicts: an empty result is not
        # sufficient evidence, because a pair that is :bot and a pair
        # that is :incomparable both contribute nothing, and a mix of
        # the two is not provably empty. Declared `Klass, Boolean`
        # narrowed by `Integer` is such a mix.
        #
        # Known gap in these rules: `Klass` against `Boolean` is
        # provably empty but comes back :incomparable, because Boolean
        # has no namespace pin for the rules to read. Closing it means
        # teaching Classification to tell a type that has no pin
        # because it is unresolved from one that has no pin because it
        # is not a namespace - a change to Classification, not to the
        # rule here.
        return :bot if disjoint?

        mixin_pairing? ? :intersect : :incomparable
      end

      private

      # @return [ApiMap]
      attr_reader :api_map

      # @return [ComplexType::UniqueType]
      attr_reader :left, :right

      # Neither side subtypes the other by the time this runs, so a
      # type admitting exactly one value cannot also be described by
      # the other side.
      #
      # A metatype - `Class<Foo>`, `Module<Bar>` - is likewise disjoint
      # from whatever else survived, with one exception: a class or
      # module object can `extend` a module, so `Class<Foo> & Mod` is
      # inhabited when Mod is one. The test is whether *the other side*
      # is a module the object could extend, not whether either side
      # mentions a module - `Module<Bar>` names a module but is the
      # thing being extended, not the thing extended onto it.
      #
      # Kept as #disjoint? rather than #bot? so it does not read as
      # UniqueType#bot?, which asks whether a type *is* bottom rather
      # than whether a pair reduces to it.
      #
      # @return [Boolean]
      def disjoint?
        return true if left_facts.singleton_valued? || right_facts.singleton_valued?
        return false if left_facts.metatype? && right_facts.extendable_module?
        return false if right_facts.metatype? && left_facts.extendable_module?

        left_facts.metatype? || right_facts.metatype?
      end

      # Whether combining these two into an intersection is safe. Only
      # true when at least one side is *positively confirmed* to be a
      # mix-in, since any class can pick up any module. Two concrete
      # classes are impossible (an object has exactly one class), and a
      # namespace with no pin is unverifiable, so both are false.
      #
      # This covers both ways a module gets mixed in: `include` on a
      # class, giving instances of it, and `extend` on a class or
      # module object, giving the metatype. #disjoint? defers the
      # metatype case here for exactly that reason.
      #
      # @return [Boolean]
      def mixin_pairing?
        left_facts.module? || right_facts.module?
      end

      # @return [Classification]
      def left_facts
        @left_facts ||= Classification.new(api_map, left)
      end

      # @return [Classification]
      def right_facts
        @right_facts ||= Classification.new(api_map, right)
      end
    end
  end
end
