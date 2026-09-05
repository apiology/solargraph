# frozen_string_literal: true

module Solargraph
  module Pin
    class BaseVariable < Base
      # include Solargraph::Source::NodeMethods
      include Solargraph::Parser::NodeMethods

      # @return [Array<Parser::AST::Node>]
      attr_reader :assignments

      attr_accessor :mass_assignment

      # @return [Range, nil]
      attr_reader :presence

      # @return [Boolean]
      attr_reader :definite

      # The CompoundStatement pin this variable's (re)assignment was
      # made within - i.e. Region#compound_statement at the point of
      # assignment. Used by #definite_reaches? to decide whether a
      # non-definite assignment still dominates a given reference.
      #
      # @return [Pin::CompoundStatement, nil]
      attr_reader :compound_statement

      # @param return_type [ComplexType, nil]
      # @param assignment [Parser::AST::Node, nil] First assignment
      #   that was made to this variable
      # @param assignments [Array<Parser::AST::Node>] Possible
      #   assignments that may have been made to this variable
      # @param mass_assignment [::Array(Parser::AST::Node, Integer, Boolean), nil]
      #   The mass assignment node, this variable's position in the
      #   left-hand side, and whether this variable is a splat target.
      # @param assignment [Parser::AST::Node, nil] First assignment
      #   that was made to this variable
      # @param assignments [Array<Parser::AST::Node>] Possible
      #   assignments that may have been made to this variable
      # @param exclude_return_type [ComplexType, nil] Ensure any
      #   return type returned will never include any of these unique
      #   types in the unique types of its complex type.
      #
      #   Example: If a return type is 'Float | Integer | nil' and the
      #   exclude_return_type is 'Integer', the resulting return
      #   type will be 'Float | nil' because Integer is excluded.
      # @param narrowed_return_type [ComplexType, nil] Ensure each unique
      #   return type is compatible with at least one element of this
      #   complex type.  If a ComplexType used as a return type is an
      #   union type - we can return any of these - this is a
      #   flow-sensitive narrowing (e.g. from an `is_a?` guard), not a
      #   real intersection type (see
      #   ComplexType::UniqueType::Intersection for that) - everything
      #   we return needs to meet at least one of these unique types.
      #
      #   Example: If a return type is 'Numeric | nil' and the
      #   narrowed_return_type is 'Float | nil', the resulting return
      #   type will be 'Float | nil' because Float is compatible
      #   with Numeric and nil is compatible with nil.
      # @see https://www.typescriptlang.org/docs/handbook/2/everyday-types.html#union-types
      # @see https://www.typescriptlang.org/docs/handbook/2/narrowing.html
      # @param presence [Range, nil]
      # @param definite [Boolean] True if this pin's assignment(s) are
      #   guaranteed to have executed at (and after) its presence's
      #   start position, as opposed to being inside a conditional
      #   branch or loop that may not run. Used to decide whether a
      #   reassignment's type may safely override a variable's
      #   previously declared/inferred type instead of merely being
      #   unioned with it.
      # @param compound_statement [Pin::CompoundStatement, nil] The
      #   CompoundStatement this variable's (re)assignment was made
      #   within. When `definite` is false, a reference whose location
      #   falls within this pin's own range may still treat the
      #   assignment as an override rather than merely unioning it
      #   with earlier possible types - see #definite_reaches?.
      # @param [Hash{Symbol => Object}] splat
      def initialize assignment: nil, assignments: [], mass_assignment: nil,
                     presence: nil, return_type: nil,
                     narrowed_return_type: nil, exclude_return_type: nil,
                     definite: true,
                     compound_statement: nil,
                     **splat
        super(**splat)
        @assignments = (assignment.nil? ? [] : [assignment]) + assignments
        # @type [nil, ::Array(Parser::AST::Node, Integer, Boolean)]
        @mass_assignment = mass_assignment
        @return_type = return_type
        @narrowed_return_type = narrowed_return_type
        @exclude_return_type = exclude_return_type
        @presence = presence
        @definite = definite
        @compound_statement = compound_statement
      end

      # @param presence [Range]
      # @param exclude_return_type [ComplexType, nil]
      # @param narrowed_return_type [ComplexType, nil]
      # @param source [::Symbol, nil]
      #
      # @return [self]
      def downcast presence:, exclude_return_type: nil, narrowed_return_type: nil,
                   source: self.source
        result = dup
        result.exclude_return_type = exclude_return_type
        result.narrowed_return_type = narrowed_return_type
        result.source = source
        result.presence = presence
        result.reset_generated!
        result
      end

      def reset_generated!
        @assignment = nil
        super
      end

      # @param other [self]
      # @param attrs [Hash]
      # @param location [Location, nil] The position being resolved,
      #   if known - used to decide whether a not-globally-definite
      #   `other` should still override us because the position falls
      #   within `other`'s compound_statement.
      def combine_with other, attrs = {}, location: nil
        superseded = override_assignments?(other, location)
        # Facts expire only when a *different* assignment overwrote the
        # value they describe.  Two flow-sensitive downcasts of the same
        # assignment - e.g. the one per operand that `a.nil? ||
        # a.empty? || a == 'x'` produces - are additional facts about
        # one value, and must accumulate rather than replace each other.
        facts_superseded = superseded && !same_assignment_sites?(other)
        new_assignments = combine_assignments(other, location)
        new_attrs = attrs.merge({
                                  # default values don't exist in RBS parameters; it just
                                  # tells you if the arg is optional or not.  Prefer a
                                  # provided value if we have one here since we can't rely on
                                  # it from RBS so we can infer from it and typecheck on it.
                                  #
                                  # When #combine_assignments supersedes rather than unions,
                                  # skip this - the constructor prepends `assignment:` to
                                  # `assignments:` unconditionally, which would re-introduce
                                  # the dropped node.
                                  assignment: superseded ? nil : choose(other, :assignment),
                                  assignments: new_assignments,
                                  mass_assignment: combine_mass_assignment(other),
                                  return_type: combine_return_type(other),
                                  # Narrowing recorded against the old value expires
                                  # when that value is definitely overwritten, so when
                                  # `other`'s assignment supersedes ours, keep only the
                                  # facts asserted about the new value.
                                  narrowed_return_type: if facts_superseded
                                                          other.narrowed_return_type
                                                        else
                                                          combine_types(other, :narrowed_return_type)
                                                        end,
                                  exclude_return_type: if facts_superseded
                                                         other.exclude_return_type
                                                       else
                                                         combine_types(other, :exclude_return_type)
                                                       end,
                                  presence: combine_presence(other),
                                  # if either side had an assignment guaranteed to
                                  # have executed, that assignment's type is
                                  # eligible to override (not just be unioned
                                  # with) the variable's other possible types
                                  definite: definite || other.definite || superseded
                                })
        super(other, new_attrs)
      end

      # @param other [self]
      #
      # @return [Array(AST::Node, Integer, Boolean), nil]
      def combine_mass_assignment other
        # @todo pick first non-nil arbitrarily - we don't yet support
        #   mass assignment merging
        mass_assignment || other.mass_assignment
      end

      # True when `other`'s assignments are the very same ones as ours,
      # identified by source position.  Structural node equality is not
      # usable here - two textually identical assignments on different
      # lines compare equal, and telling those apart is the whole point.
      #
      # @param other [self]
      # @return [Boolean]
      def same_assignment_sites? other
        assignment_sites == other.assignment_sites
      end

      # @return [::Array<Solargraph::Range, nil>]
      def assignment_sites
        assignments.map { |node| Solargraph::Range.from_node(node) }
      end

      # @return [Parser::AST::Node, nil]
      def assignment
        @assignment ||= assignments.last
      end

      # @param other [self]
      #
      # @param other [self]
      # @param location [Location, nil]
      # @return [::Array<Parser::AST::Node>]
      def combine_assignments other, location = nil
        return other.assignments.dup if override_assignments?(other, location)

        (other.assignments + assignments).uniq
      end

      def inner_desc
        super + ", presence=#{presence.inspect}, assignments=#{assignments}, " \
                "narrowed_return_type=#{narrowed_return_type&.rooted_tags.inspect}, " \
                "exclude_return_type=#{exclude_return_type&.rooted_tags.inspect}"
      end

      def completion_item_kind
        Solargraph::LanguageServer::CompletionItemKinds::VARIABLE
      end

      # @return [Integer]
      def symbol_kind
        Solargraph::LanguageServer::SymbolKinds::VARIABLE
      end

      def nil_assignment?
        # this will always be false - should it be return_type ==
        #   ComplexType::NIL or somesuch?
        return_type.nil?
      end

      def variable?
        true
      end

      # @param parent_node [Parser::AST::Node]
      # @param api_map [ApiMap]
      # @return [::Array<ComplexType>]
      def return_types_from_node parent_node, api_map
        types = []
        value_position_nodes_only(parent_node).each do |node|
          # Nil nodes may not have a location
          if node.nil? || node.type == :NIL || node.type == :nil
            types.push ComplexType::NIL
          else
            rng = Range.from_node(node)
            next if rng.nil?
            pos = rng.ending
            # @sg-ignore Need to add nil check here
            clip = api_map.clip_at(location.filename, pos)
            # Use the return node for inference. The clip might infer from the
            # first node in a method call instead of the entire call.
            chain = Parser.chain(node, nil, nil)
            # Exclude this assignment's own pin(s) from RHS resolution - a
            # self-reference (e.g. `a = a`) must resolve against the
            # variable's *other* assignments, not the value being derived.
            #
            # Array#include? compares with #==, and Parser::AST::Node#==
            # is structural (type + children), not identity - two
            # unrelated call nodes with the same shape (e.g. two separate
            # bare `steps` calls at different source locations) compare
            # equal. Using #include? here would wrongly treat an
            # unrelated candidate - e.g. a flow-sensitive-typing pin
            # synthesized from an earlier, textually-identical guard call
            # like `steps.nil?` - as this assignment's own pin, and
            # exclude it from candidates to resolve `steps` against here,
            # discarding its narrowing. Compare by identity instead.
            self_excluded_locals = clip.locals.reject do |candidate|
              candidate.assignments.any? { |a| a.equal?(parent_node) }
            end
            # @sg-ignore Need to add nil check here
            result = chain.infer(api_map, closure, self_excluded_locals).self_to_type(closure.context)
            types.push result unless result.undefined?
          end
        end
        types
      end

      # The literal-key-preserving "record" inference of this variable's
      # single assignment, used only to re-check an initial Hash-literal
      # assignment against a declared record-type expectation
      # (Hash{:k1 => V1} & Hash{:k2 => V2} & ...) that #probe's merged
      # Hash{K => V} result can't express - see
      # Source::Chain::Hash#record_type and
      # ComplexType::UniqueType::Intersection#conforms_to_record_subset?.
      #
      # @param api_map [ApiMap]
      # @return [ComplexType, nil]
      def record_type api_map
        return nil unless assignments.length == 1

        node = assignments.first
        return nil if node.nil?

        rng = Range.from_node(node)
        return nil if rng.nil?

        pin_location = location
        pin_closure = closure
        return nil if pin_location.nil? || pin_closure.nil?

        clip = api_map.clip_at(pin_location.filename, rng.ending)
        chain = Parser.chain(node, nil, nil)
        link = chain.links.last
        return nil unless link.is_a?(Solargraph::Source::Chain::Hash)

        link.record_type(api_map, pin_closure, clip.locals)
      end

      # @param api_map [ApiMap]
      # @return [ComplexType, ComplexType::UniqueType]
      def probe api_map
        assignment_types = assignments.flat_map { |node| return_types_from_node(node, api_map) }
        unless assignment_types.empty?
          # @type [Array<ComplexType::UniqueType>]
          items = assignment_types.flat_map(&:items).uniq
          # A later, wider assignment (e.g. `index += n`) can leave a
          # stale literal (e.g. `0`) alongside its own non-literal
          # base type in the union - drop the redundant literal.
          type_from_assignment = ComplexType.new(items).without_redundant_literals
        end
        return adjust_type api_map, type_from_assignment unless type_from_assignment.nil?

        # @todo should handle merging types from mass assignments as
        #   well so that we can do better flow sensitive typing with
        #   multiple assignments
        unless @mass_assignment.nil?
          mass_node, index, splat = @mass_assignment
          types = return_types_from_node(mass_node, api_map)
          # rubocop:disable Style/ConditionalAssignment
          if splat
            # A splat target (`*args`) captures every remaining
            # element of the right-hand side, not just one position -
            # take the source array's full parameter union rather
            # than a single indexed/first parameter.
            types = types.flat_map do |type|
              if type.tuple? || splattable?(api_map, type)
                type.all_params
              else
                []
              end
            end
          else
            types = types.flat_map do |type|
              if type.tuple?
                # A true tuple's positions are heterogeneous, so only
                # the position actually being assigned applies here.
                [type.all_params[index]].compact
              elsif splattable?(api_map, type)
                # A non-tuple Array-like type (e.g. Array<Integer,
                # String>) declares a union of possible element types,
                # not a positional tuple - every position can hold any
                # member of that union, so the whole union applies.
                type.all_params
              else
                []
              end
            end
          end
          # rubocop:enable Style/ConditionalAssignment

          return ComplexType::UNDEFINED if types.empty?

          element_type = ComplexType.new(types.uniq)
          # A splat target (`*args`) captures the rest of the
          # right-hand side as an array of the element type, not the
          # element type itself.
          if splat
            rest_type = ComplexType::UniqueType.new('Array', [], [element_type], rooted: true, parameters_type: :list)
            return adjust_type api_map, ComplexType.new([rest_type]).qualify(api_map, *gates)
          end

          return adjust_type api_map, element_type.qualify(api_map, *gates)
        end

        ComplexType::UNDEFINED
      end

      # @param other [Object]
      def == other
        return false unless other.is_a?(BaseVariable)
        return false unless super
        return false unless assignment == other.assignment
        # combine_with results choose the earliest assignment's
        # #location, so two combined pins covering a different number
        # of assignments to the same variable can share #location while
        # covering different #presence ranges - e.g. one pin combined
        # through a variable's first reassignment, another combined
        # through its second. Base#== doesn't compare presence, so
        # without this check those pins looked identical to any caller
        # keying off of #== (e.g. Array#include?).
        presence == other.presence &&
          narrowed_return_type == other.narrowed_return_type &&
          exclude_return_type == other.exclude_return_type
      end

      def type_desc
        "#{super} = #{assignment&.type.inspect}"
      end

      # @return [ComplexType, nil]
      def return_type
        generate_complex_type || @return_type || narrowed_return_type || ComplexType::UNDEFINED
      end

      def typify api_map
        raw_return_type = super

        adjust_type(api_map, raw_return_type)
      end

      # A merged multi-assignment pin and its earliest assignment share the
      # same #choose-d location but differ in presence, which is what keeps
      # Chain's recursion guard from conflating the two and dropping a valid lookup.
      #
      # @return [String, nil]
      def identity_discriminator
        presence&.hash&.to_s
      end

      # @sg-ignore need boolish support for ? methods
      def presence_certain?
        exclude_return_type || narrowed_return_type
      end

      # @param other_loc [Location]
      def starts_at? other_loc
        location&.filename == other_loc.filename &&
          presence &&
          presence.start == other_loc.range.start
      end

      # Narrow the presence range to the intersection of both.
      #
      # @param other [self]
      #
      # @return [Range, nil]
      def combine_presence other
        return presence || other.presence if presence.nil? || other.presence.nil?

        # @sg-ignore https://github.com/castwide/solargraph/issues/1249
        Range.new([presence.start, other.presence.start].max, [presence.ending, other.presence.ending].min)
      end

      # @param other [self]
      # @return [Pin::Closure, nil]
      def combine_closure other
        return closure if closure == other.closure

        # choose first defined, as that establishes the scope of the variable
        if closure.nil? || other.closure.nil?
          Solargraph.assert_or_log(:varible_closure_missing) do
            'One of the local variables being combined is missing a closure: ' \
              "#{inspect} vs #{other.inspect}"
          end
          return closure || other.closure
        end

        if closure.location.nil? || other.closure.location.nil?
          return closure.location.nil? ? other.closure : closure
        end

        # if filenames are different, this will just pick one
        return closure if closure.location <= other.closure.location

        other.closure
      end

      # @param other_closure [Pin::Closure]
      # @param other_loc [Location]
      def visible_at? other_closure, other_loc
        # @sg-ignore https://github.com/castwide/solargraph/issues/1249
        location.filename == other_loc.filename &&
          (!presence || presence.include?(other_loc.range.start)) &&
          !within_own_assignment?(other_loc) &&
          visible_in_closure?(other_closure)
      end

      protected

      attr_accessor :exclude_return_type, :narrowed_return_type

      # @return [Range]
      # @sg-ignore Need to add nil check here
      attr_writer :presence

      # Downcast pins share name/location/closure; must differ by narrowing facts too.
      #
      # @return [::Array]
      def equality_fields
        super + [presence, narrowed_return_type, exclude_return_type]
      end

      public

      # True if `other_loc` falls inside the source range of one of this
      # pin's own assignment value nodes - i.e., `other_loc` is
      # resolving a reference that occurs *while* one of this
      # variable's own assignments is still being evaluated, such as
      # the receiver `x` in a self-referential reassignment (`x =
      # x.length`, or `index += 1` desugared to `index = index + 1`).
      # That reference must resolve against this variable's *other*
      # assignments, not against the not-yet-assigned value being
      # derived here, even though `other_loc` otherwise falls within
      # this pin's presence.
      #
      # @param other_loc [Location]
      # @return [Boolean]
      def within_own_assignment? other_loc
        return false unless location&.filename == other_loc.filename

        assignments.any? do |assignment_node|
          next false unless assignment_node.respond_to?(:loc)

          rng = Range.from_node(assignment_node)
          next false if rng.nil?

          # The position immediately at/after the assignment node's own
          # end is where its new value becomes visible - only exclude
          # positions strictly *inside* the node (i.e. still being
          # evaluated), not that boundary itself.
          rng.contain?(other_loc.range.start) && other_loc.range.start != rng.ending
        end
      end

      private

      # True if `other`'s assignment(s) should supersede ours
      # instead of merely being unioned with them: `other` reassigns
      # the same variable, in the same scope, via an assignment
      # guaranteed to have executed, so by the time `other`'s
      # presence begins our value has definitely been overwritten.
      #
      # Excludes self-referential reassignments (`x = x.foo`,
      # desugared `+=`, etc.) - resolving their right-hand side needs
      # our assignment(s) as the base case, so dropping them would
      # leave nothing to resolve against.
      #
      # @param other [self]
      # @param location [Location, nil] The position being resolved,
      #   if known - lets a conditional `other` still override us when
      #   `location` falls within `other`'s compound_statement.
      # @return [Boolean]
      def override_assignments? other, location = nil
        (other.definite || other.definite_reaches?(location)) && other.closure == closure &&
          other.assignments.none? { |node| references_name?(node) }
      end

      public

      # True if this pin's assignment, though not globally definite,
      # is still guaranteed to dominate `location` - i.e., `location`
      # falls within the CompoundStatement body (an if/while/until/
      # rescue/&&/||/||= branch) this assignment was made in, so no
      # earlier branch exit could have skipped it by the time
      # `location` is reached. A nested CompoundStatement's location
      # is always a subrange of its parent's, so this single
      # containment check already accounts for arbitrarily nested
      # branches without walking the compound_statement chain further.
      #
      # @param location [Location, nil]
      # @return [Boolean]
      def definite_reaches? location
        cs = compound_statement
        return false unless location && cs&.location&.range

        # @sg-ignore flow sensitive typing needs to handle attrs
        cs.location.filename == location.filename &&
          # @sg-ignore flow sensitive typing needs to handle attrs
          cs.location.range.contain?(location.range.start)
      end

      private

      # @param node [Parser::AST::Node, nil]
      # @return [Boolean]
      def references_name? node
        return false unless node.is_a?(::AST::Node)

        return true if %i[lvar ivar].include?(node.type) && node.children[0].to_s == name

        # A block parameter of the same name shadows us for the whole
        # block, so any mention inside the body is the parameter, not
        # this variable.  The receiver (children[0]) is evaluated
        # outside the block, so it still counts.
        return references_name?(node.children[0]) if shadowed_by_block_parameter?(node)

        node.children.any? { |child| references_name?(child) }
      end

      # @param node [::AST::Node]
      # @return [Boolean]
      def shadowed_by_block_parameter? node
        return false unless node.type == :block

        args = node.children[1]
        return false unless args.is_a?(::AST::Node)

        args.children.any? do |arg|
          arg.is_a?(::AST::Node) && arg.children[0].to_s == name
        end
      end

      # True for a type destructurable by a splat/multi-assignment target -
      # Array/Set/Enumerable by name, or anything structurally Enumerable.
      #
      # @param api_map [ApiMap]
      # @param type [ComplexType]
      # @return [Boolean]
      def splattable? api_map, type
        return true if ['::Array', '::Set', '::Enumerable'].include?(type.rooted_name)

        enumerable = ComplexType.parse('::Enumerable').qualify(api_map)
        type.qualify(api_map).conforms_to?(api_map, enumerable, :assignment)
      end

      # @param api_map [ApiMap]
      # @param raw_return_type [ComplexType, ComplexType::UniqueType]
      #
      # @return [ComplexType, ComplexType::UniqueType]
      def adjust_type api_map, raw_return_type
        qualified_exclude = exclude_return_type&.qualify(api_map, *(closure&.gates || ['']))
        minus_exclusions = raw_return_type.exclude qualified_exclude, api_map
        qualified_narrowing = narrowed_return_type&.qualify(api_map, *(closure&.gates || ['']))
        minus_exclusions.narrow_with qualified_narrowing, api_map
      end

      # See if this variable is visible within 'viewing_closure'
      #
      # @param viewing_closure [Pin::Closure]
      # @return [Boolean]
      def visible_in_closure? viewing_closure
        return false if closure.nil?

        # if we're declared at top level, we can't be seen from within
        # methods declared tere

        return false if viewing_closure.is_a?(Pin::Method) && closure.context.tags == 'Class<>'

        return true if viewing_closure.binder.namespace == closure.binder.namespace

        return true if viewing_closure.return_type == closure.context

        # classes and modules can't see local variables declared
        # in their parent closure, so stop here
        return false if scope == :instance && viewing_closure.is_a?(Pin::Namespace)

        parent_of_viewing_closure = viewing_closure.closure

        return false if parent_of_viewing_closure.nil?

        visible_in_closure?(parent_of_viewing_closure)
      end

      # @param other [self]
      # @return [ComplexType, nil]
      def combine_return_type other
        combine_types(other, :return_type)
      end

      # @param other [self]
      # @param attr [::Symbol]
      #
      # @return [ComplexType, nil]
      def combine_types other, attr
        # @type [ComplexType, nil]
        type1 = send(attr)
        # @type [ComplexType, nil]
        type2 = other.send(attr)
        if type1 && type2
          types = (type1.items + type2.items).uniq
          ComplexType.new(types)
        else
          type1 || type2
        end
      end

      # @return [::Symbol]
      def scope
        :instance
      end

      # @return [ComplexType, nil]
      def generate_complex_type
        tag = docstring.tag(:type)
        return ComplexType.try_parse(*tag.types) unless tag.nil? || tag.types.nil? || tag.types.empty?
        nil
      end
    end
  end
end
