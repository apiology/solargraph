# frozen_string_literal: true

module Solargraph
  module Parser
    class FlowSensitiveTyping
      include Solargraph::Parser::NodeMethods

      # `kind_of?` is an alias of `is_a?`, with the same semantics on
      # both paths: a true result proves class membership, and a false
      # result rules out the class and every subclass of it. Both are
      # handled by #parse_isa.
      ISA_METHOD_NAMES = %i[is_a? kind_of?].freeze

      # @param locals [Array<Solargraph::Pin::LocalVariable>]
      # @param ivars [Array<Solargraph::Pin::InstanceVariable>]
      # @param enclosing_breakable_pin [Solargraph::Pin::Breakable, nil]
      # @param enclosing_compound_statement_pin [Solargraph::Pin::CompoundStatement, nil]
      # @param closure [Solargraph::Pin::Closure] The pin enclosing the
      #   code being processed (e.g. the current method), used to
      #   resolve a bare, implicit-self call like 'steps' as a call to
      #   a 0-arg method rather than a local variable, and to synthesize
      #   a pin for an instance variable that has no assignment anywhere
      #   in scope (see #process_instance_variable_defined).
      # @param only_downcast_these_names [Array<String>, nil] If given,
      #   only apply a downcast to variables with these names, ignoring
      #   any other variable the analyzed condition happens to mention.
      def initialize locals, ivars, enclosing_breakable_pin, enclosing_compound_statement_pin, closure,
                     only_downcast_these_names: nil
        @locals = locals
        @ivars = ivars
        @enclosing_breakable_pin = enclosing_breakable_pin
        @enclosing_compound_statement_pin = enclosing_compound_statement_pin
        @closure = closure
        @only_downcast_these_names = only_downcast_these_names
      end

      # Assert the facts implied by a condition being true/false over
      # the given ranges.  Public so that a differently-configured
      # instance (see #initialize's only_downcast_these_names) can be handed a
      # condition to analyze.
      #
      # @param conditional_node [Parser::AST::Node]
      # @param true_ranges [Array<Range>]
      # @param false_ranges [Array<Range>]
      #
      # @return [void]
      def process_condition conditional_node, true_ranges, false_ranges
        process_expression(conditional_node, true_ranges, false_ranges)
      end

      # @param and_node [Parser::AST::Node]
      # @param true_ranges [Array<Range>]
      # @param false_ranges [Array<Range>]
      #
      # @return [void]
      def process_and and_node, true_ranges = [], false_ranges = []
        return unless and_node.type == :and

        # @type [Parser::AST::Node]
        # @sg-ignore Need to add nil check here
        lhs = and_node.children[0]
        # @type [Parser::AST::Node]
        # @sg-ignore Need to add nil check here
        rhs = and_node.children[1]

        before_rhs_loc = rhs.location.expression.adjust(begin_pos: -1)
        before_rhs_pos = Position.new(before_rhs_loc.line, before_rhs_loc.column)

        rhs_presence = Range.new(before_rhs_pos,
                                 get_node_end_position(rhs))

        # can't assume if an and is false that every single condition
        # is false, so don't provide any false ranges to assert facts
        # on
        process_expression(lhs, true_ranges + [rhs_presence], [])
        process_expression(rhs, true_ranges, [])
      end

      # @param or_node [Parser::AST::Node]
      # @param true_ranges [Array<Range>]
      # @param false_ranges [Array<Range>]
      #
      # @return [void]
      def process_or or_node, true_ranges = [], false_ranges = []
        return unless or_node.type == :or

        # @type [Parser::AST::Node]
        # @sg-ignore Need to add nil check here
        lhs = or_node.children[0]
        # @type [Parser::AST::Node]
        # @sg-ignore Need to add nil check here
        rhs = or_node.children[1]

        before_rhs_loc = rhs.location.expression.adjust(begin_pos: -1)
        before_rhs_pos = Position.new(before_rhs_loc.line, before_rhs_loc.column)

        rhs_presence = Range.new(before_rhs_pos,
                                 get_node_end_position(rhs))

        # can assume if an or is false that every single condition is
        # false, so provide false ranges to assert facts on

        # can't assume if an or is true that every single condition is
        # true, so don't provide true ranges to assert facts on to
        # each side individually - however, if both sides are
        # `is_a?` checks on the same variable, we can narrow that
        # variable to the union of the checked types
        process_or_isa_union(or_node, lhs, rhs, true_ranges)

        process_expression(lhs, [], false_ranges + [rhs_presence])
        process_expression(rhs, [], false_ranges)
      end

      # @param node [Parser::AST::Node]
      # @param true_presences [Array<Range>]
      # @param false_presences [Array<Range>]
      #
      # @return [void]
      def process_calls node, true_presences, false_presences
        return unless node.type == :send

        process_isa(node, true_presences, false_presences)
        process_respond_to(node, true_presences, false_presences)
        process_instance_of(node, true_presences, false_presences)
        process_instance_variable_defined(node, true_presences, false_presences)
        process_nilp(node, true_presences, false_presences)
        process_bang(node, true_presences, false_presences)
        process_eq(node, true_presences, false_presences)
        process_neq(node, true_presences, false_presences)
      end

      # @param if_node [Parser::AST::Node]
      # @param true_ranges [Array<Range>]
      # @param false_ranges [Array<Range>]
      #
      # @return [void]
      def process_if if_node, true_ranges = [], false_ranges = []
        return if if_node.type != :if

        #
        # See if we can refine a type based on the result of 'if foo.nil?'
        #
        # [3] pry(main)> require 'parser/current'; Parser::CurrentRuby.parse("if foo.is_a? Baz; then foo; else bar; end")
        # => s(:if,
        #   s(:send,
        #     s(:send, nil, :foo), :is_a?,
        #     s(:const, nil, :Baz)),
        #   s(:send, nil, :foo),
        #   s(:send, nil, :bar))
        # [4] pry(main)>
        conditional_node = if_node.children[0]
        # @type [Parser::AST::Node, nil]
        then_clause = if_node.children[1]
        # @type [Parser::AST::Node, nil]
        else_clause = if_node.children[2]

        unless enclosing_breakable_pin.nil?
          rest_of_breakable_body = Range.new(get_node_end_position(if_node),
                                             get_node_end_position(enclosing_breakable_pin.node))

          false_ranges << rest_of_breakable_body if always_breaks?(then_clause)

          true_ranges << rest_of_breakable_body if always_breaks?(else_clause)
        end

        unless enclosing_compound_statement_pin.node.nil?
          rest_of_returnable_body = Range.new(get_node_end_position(if_node),
                                              get_node_end_position(enclosing_compound_statement_pin.node))

          #
          # if one of the clauses always leaves the compound
          # statement, we can assume things about the rest of the
          # compound statement
          #
          false_ranges << rest_of_returnable_body if always_leaves_compound_statement?(then_clause)

          true_ranges << rest_of_returnable_body if always_leaves_compound_statement?(else_clause)
        end

        unless then_clause.nil?
          #
          # If the condition is true we can assume things about the then clause
          #
          before_then_clause_loc = then_clause.location.expression.adjust(begin_pos: -1)
          before_then_clause_pos = Position.new(before_then_clause_loc.line, before_then_clause_loc.column)
          true_ranges << Range.new(before_then_clause_pos,
                                   get_node_end_position(then_clause))
        end

        unless else_clause.nil?
          #
          # If the condition is true we can assume things about the else clause
          #
          before_else_clause_loc = else_clause.location.expression.adjust(begin_pos: -1)
          before_else_clause_pos = Position.new(before_else_clause_loc.line, before_else_clause_loc.column)
          false_ranges << Range.new(before_else_clause_pos,
                                    get_node_end_position(else_clause))
        end

        # @sg-ignore Need to add nil check here
        process_expression(conditional_node, true_ranges, false_ranges)

        # @sg-ignore RBS Array[self] indexing infers Array instead of self
        process_guarded_reassignment(if_node, conditional_node, then_clause, else_clause)
      end

      # @param while_node [Parser::AST::Node]
      # @param true_ranges [Array<Range>]
      # @param false_ranges [Array<Range>]
      #
      # @return [void]
      def process_while while_node, true_ranges = [], false_ranges = []
        return if while_node.type != :while

        #
        # See if we can refine a type based on the result of 'if foo.nil?'
        #
        # [3] pry(main)> Parser::CurrentRuby.parse("while a; b; c; end")
        # => s(:while,
        #   s(:send, nil, :a),
        #   s(:begin,
        #     s(:send, nil, :b),
        #     s(:send, nil, :c)))
        # [4] pry(main)>
        conditional_node = while_node.children[0]
        # @type [Parser::AST::Node, nil]
        do_clause = while_node.children[1]

        unless do_clause.nil?
          #
          # If the condition is true we can assume things about the do clause
          #
          before_do_clause_loc = do_clause.location.expression.adjust(begin_pos: -1)
          before_do_clause_pos = Position.new(before_do_clause_loc.line, before_do_clause_loc.column)
          true_ranges << Range.new(before_do_clause_pos,
                                   get_node_end_position(do_clause))
        end

        # @sg-ignore Need to add nil check here
        process_expression(conditional_node, true_ranges, false_ranges)
      end

      # @param case_node [Parser::AST::Node]
      #
      # @return [void]
      def process_case case_node
        return if case_node.type != :case

        #
        # See if we can narrow the subject's type inside each 'when'
        # branch based on the classes tested for in that branch
        #
        # [3] pry(main)> Parser::CurrentRuby.parse("case a; when B; c; end")
        # => s(:case,
        #   s(:send, nil, :a),
        #   s(:when,
        #     s(:const, nil, :B),
        #     s(:send, nil, :c)), nil)
        # [4] pry(main)>
        subject_node = case_node.children[0]
        return if subject_node.nil?
        return unless %i[lvar ivar].include?(subject_node.type)

        variable_name = parse_variable(subject_node)
        return if variable_name.nil?

        # @sg-ignore Need to add nil check here
        subject_position = Range.from_node(subject_node).start
        pin = find_var(variable_name, subject_position)
        return unless pin

        # @sg-ignore Need to add nil check here
        when_nodes = case_node.children[1..].compact.select { |child| child.type == :when }
        # @sg-ignore flow sensitive typing needs to narrow down type with an if is_a? check
        when_nodes.each do |when_node|
          *value_nodes, body_node = when_node.children
          next if body_node.nil?

          type_names = value_nodes.map { |value_node| type_name(value_node) }
          # Only narrow if every value in this 'when' clause is a
          # simple constant reference - a splat, range, regexp, etc.
          # isn't a type we can express as a downcast.
          next if type_names.any?(&:nil?)

          before_body_loc = body_node.location.expression.adjust(begin_pos: -1)
          before_body_pos = Position.new(before_body_loc.line, before_body_loc.column)
          presence = Range.new(before_body_pos, get_node_end_position(body_node))

          facts = { pin => [{ type: ComplexType.parse(*type_names) }] }
          process_facts(facts, [presence])
        end
      end

      # @param or_asgn_node [Parser::AST::Node]
      # @param presence [Range]
      #
      # @return [void]
      def process_or_asgn or_asgn_node, presence
        return if or_asgn_node.type != :or_asgn

        #
        # 'x ||= value' only actually assigns when x is falsy (nil or
        # false), so if x was already truthy, it keeps whatever
        # non-nil type it already had. Narrow the existing pin by
        # excluding nil, scoped to the rest of the enclosing closure.
        #
        # [3] pry(main)> Parser::CurrentRuby.parse("x ||= 1")
        # => s(:or_asgn,
        #   s(:lvasgn, :x),
        #   s(:int, 1))
        # [4] pry(main)>
        lhs = or_asgn_node.children[0]
        # @sg-ignore Parser::AST::Node#children is declared to return a bare Array, losing its element type here
        return unless %i[lvasgn ivasgn].include?(lhs.type)

        # @sg-ignore Parser::AST::Node#children is declared to return a bare Array, losing its element type here
        variable_name = lhs.children[0].to_s
        # @sg-ignore Parser::AST::Node#children is declared to return a bare Array, losing its element type here
        return if variable_name.empty?

        range = Range.from_node(or_asgn_node)
        return if range.nil?

        position = range.start
        pin = find_var(variable_name, position)
        return unless pin

        facts = { pin => [{ not_type: ComplexType::NIL }] }
        process_facts(facts, [presence])
      end

      # @param until_node [Parser::AST::Node]
      # @param true_ranges [Array<Range>]
      # @param false_ranges [Array<Range>]
      #
      # @return [void]
      def process_until until_node, true_ranges = [], false_ranges = []
        return if until_node.type != :until

        # [3] pry(main)> Parser::CurrentRuby.parse("until a; b; c; end")
        # => s(:until,
        #   s(:send, nil, :a),
        #   s(:begin,
        #     s(:send, nil, :b),
        #     s(:send, nil, :c)))
        # [4] pry(main)>
        conditional_node = until_node.children[0]
        return if conditional_node.nil?

        # @type [Parser::AST::Node, nil]
        do_clause = until_node.children[1]

        unless do_clause.nil?
          #
          # The do clause runs only while the condition is false, so
          # the condition's false facts hold throughout it.  Nothing
          # is asserted after the loop - the body may run zero times,
          # and a break can leave it with the condition still false.
          #
          before_do_clause_loc = do_clause.location.expression.adjust(begin_pos: -1)
          before_do_clause_pos = Position.new(before_do_clause_loc.line, before_do_clause_loc.column)
          false_ranges << Range.new(before_do_clause_pos,
                                    get_node_end_position(do_clause))
        end

        process_expression(conditional_node, true_ranges, false_ranges)
      end

      class << self
        include Logging
      end

      include Logging

      private

      # The standard default-argument idiom reassigns a variable in
      # the branch where the guard on that same variable fired:
      #
      #   tasks = ['a'] if tasks.nil?
      #   tasks.each { ... }
      #
      # At a use site *after* the conditional, the two incoming paths
      # are (a) the guard fired and the clause assigned a new value,
      # and (b) the guard did not fire, leaving the original value -
      # which the condition tells us something about.  Path (a) is
      # already handled: the assignment's pin is unioned in.  Path (b)
      # is what's asserted here - the opposite branch's facts from the
      # condition hold over the rest of the enclosing compound
      # statement.
      #
      # The facts are restricted to the variables the clause
      # definitely reassigns.  Without that restriction a condition
      # like `x.nil? || y.nil?` would wrongly narrow `y` after the
      # conditional, since the clause only replaced `x`'s value.
      #
      # @param if_node [Parser::AST::Node]
      # @param conditional_node [Parser::AST::Node]
      # @param then_clause [Parser::AST::Node, nil]
      # @param else_clause [Parser::AST::Node, nil]
      #
      # @return [void]
      def process_guarded_reassignment if_node, conditional_node, then_clause, else_clause
        compound_statement_node = enclosing_compound_statement_pin&.node
        return if compound_statement_node.nil?

        rest_of_compound_statement = Range.new(get_node_end_position(if_node),
                                               get_node_end_position(compound_statement_node))

        # the then clause ran only when the condition was true, so the
        # path that preserved the original value is the false one -
        # and vice versa for the else clause
        assert_after_guard(conditional_node, definitely_assigned_names(then_clause),
                           [], [rest_of_compound_statement])
        assert_after_guard(conditional_node, definitely_assigned_names(else_clause),
                           [rest_of_compound_statement], [])
      end

      # "Assert" here means apply, not check: names is already known
      # to be assigned unconditionally on the ranges given (the
      # guard's own then/else clause), so this pushes the condition's
      # narrowed types into effect for that code as an established
      # fact, rather than testing anything at runtime.
      #
      # @param conditional_node [Parser::AST::Node]
      # @param names [Array<String>]
      # @param true_ranges [Array<Range>]
      # @param false_ranges [Array<Range>]
      #
      # @return [void]
      def assert_after_guard conditional_node, names, true_ranges, false_ranges
        return if names.empty?

        FlowSensitiveTyping.new(locals, ivars, enclosing_breakable_pin, enclosing_compound_statement_pin,
                                closure, only_downcast_these_names: names)
                           .process_condition(conditional_node, true_ranges, false_ranges)
      end

      # Names of the variables this clause assigns on every path
      # through it.  Only unconditional, plain assignments count -
      # anything inside a nested conditional or loop may not run, and
      # `||=`/`+=`-style assignments keep the previous value in play.
      #
      # @param clause_node [Parser::AST::Node, nil]
      #
      # @return [Array<String>]
      def definitely_assigned_names clause_node
        return [] if clause_node.nil?

        case clause_node.type
        when :lvasgn, :ivasgn
          [clause_node.children[0].to_s]
        when :begin, :kwbegin
          clause_node.children.flat_map { |child| definitely_assigned_names(child) }
        else
          []
        end
      end

      # @param pin [Pin::BaseVariable]
      # @param presence [Range]
      # @param downcast_type [ComplexType, nil]
      # @param downcast_not_type [ComplexType, nil]
      #
      # @return [void]
      def add_downcast_var pin, presence:, downcast_type:, downcast_not_type:
        return if only_downcast_these_names && !only_downcast_these_names.include?(pin.name)

        new_pin = pin.downcast(exclude_return_type: downcast_not_type,
                               narrowed_return_type: downcast_type,
                               source: :flow_sensitive_typing,
                               presence: presence)
        if pin.is_a?(Pin::LocalVariable)
          locals.push(new_pin)
        elsif pin.is_a?(Pin::InstanceVariable)
          ivars.push(new_pin)
        else
          raise "Tried to add invalid pin type #{pin.class} in FlowSensitiveTyping"
        end
      end

      # @param facts_by_pin [Hash{Pin::BaseVariable => Array<Hash{:type, :not_type => ComplexType}>}]
      # @param presences [Array<Range>]
      #
      # @return [void]
      def process_facts facts_by_pin, presences
        #
        # Add specialized vars for the rest of the block
        #
        facts_by_pin.each_pair do |pin, facts|
          facts.each do |fact|
            downcast_type = fact.fetch(:type, nil)
            downcast_not_type = fact.fetch(:not_type, nil)
            presences.each do |presence|
              add_downcast_var(pin,
                               presence: presence,
                               downcast_type: downcast_type,
                               downcast_not_type: downcast_not_type)
            end
          end
        end
      end

      # @param expression_node [Parser::AST::Node]
      # @param true_ranges [Array<Range>]
      # @param false_ranges [Array<Range>]
      #
      # @return [void]
      def process_expression expression_node, true_ranges, false_ranges
        process_calls(expression_node, true_ranges, false_ranges)
        process_and(expression_node, true_ranges, false_ranges)
        process_or(expression_node, true_ranges, false_ranges)
        process_parentheses(expression_node, true_ranges, false_ranges)
        process_assignment(expression_node, true_ranges, false_ranges)
        process_variable(expression_node, true_ranges, false_ranges)
        process_call_chain(expression_node, true_ranges, false_ranges)
      end

      # Recognizes receivers shaped like 'foo', '@foo', 'foo.bar', or
      # '@foo.bar.baz' -- a chain of simple, argument-less, blockless
      # calls/variables rooted in a local, ivar, or unresolved name.
      #
      # @param node [Parser::AST::Node, nil]
      # @return [::Array<String>, nil] Dotted-word chain, e.g. ['pin',
      #   'location'], or nil if `node` doesn't have this shape.
      def parse_receiver_chain node
        return unless node.is_a?(::Parser::AST::Node)
        return [node.children[0].to_s] if %i[lvar ivar].include?(node.type)
        return unless node.type == :send
        # no arguments -- children[2..] is only nil (rather than [])
        # if the start index is out of bounds, which can't happen here
        return unless (node.children[2..] || []).empty?

        method_name = node.children[1]
        return unless method_name.is_a?(Symbol)

        receiver = node.children[0]
        # bare call, e.g. `s(:send, nil, :foo)` - implicit self, so
        # 'foo' could be a local variable or a 0-arg method on self
        return [method_name.to_s] if receiver.nil?

        #   AST::Node, never any of the other types children[] can hold
        #   for other node shapes (e.g. Symbol, Array) -- and
        #   parse_receiver_chain re-checks node.is_a?(...) itself anyway
        base = parse_receiver_chain(receiver)
        return unless base

        base + [method_name.to_s]
      end

      # `(foo)` parses as a one-child :begin wrapping the expression,
      # which is how an assignment used as a condition normally shows
      # up: `if (md = foo.match(...))`.  A multi-statement :begin
      # takes its truthiness from the last statement, which isn't
      # worth handling here.
      #
      # @param node [Parser::AST::Node]
      # @param true_ranges [Array<Range>]
      # @param false_ranges [Array<Range>]
      #
      # @return [void]
      def process_parentheses node, true_ranges, false_ranges
        return unless node.type == :begin && node.children.length == 1

        child = node.children[0]
        return unless child.is_a?(::Parser::AST::Node)

        process_expression(child, true_ranges, false_ranges)
      end

      # An assignment used as a condition - `if (md = foo.match(...))`
      # - evaluates to the value assigned, so the branches tell us the
      # same thing about the variable that a bare reference to it
      # would.
      #
      # @param node [Parser::AST::Node]
      # @param true_presences [Array<Range>]
      # @param false_presences [Array<Range>]
      #
      # @return [void]
      def process_assignment node, true_presences, false_presences
        return unless %i[lvasgn ivasgn].include?(node.type)

        variable_name = node.children[0]&.to_s
        return if variable_name.nil? || variable_name.empty?

        # look the variable up at the end of its own assignment, where
        # the new value has become visible
        pin = find_var(variable_name, get_node_end_position(node))
        return unless pin

        # @type Hash{Pin::BaseVariable => Array<Hash{Symbol => ComplexType}>}
        if_true = { pin => [{ not_type: ComplexType::NIL }] }
        process_facts(if_true, true_presences)

        # @type Hash{Pin::BaseVariable => Array<Hash{Symbol => ComplexType}>}
        if_false = { pin => [{ type: ComplexType.parse('nil, false') }] }
        process_facts(if_false, false_presences)
      end

      # @param call_node [Parser::AST::Node]
      # @param method_name [Symbol]
      # @return [Array(String, ::Array<String>), nil] Tuple of argument to
      #   function, then dotted-word chain for the receiver, otherwise nil
      #   if the receiver isn't a simple chain (see #parse_receiver_chain)
      def parse_call call_node, method_name
        return unless call_node&.type == :send && call_node.children[1] == method_name
        # Check if conditional node follows this pattern:
        #   s(:send,
        #     s(:send, nil, :foo), :is_a?,
        #     s(:const, nil, :Baz)),
        #
        call_receiver = call_node.children[0]
        # @sg-ignore Need to add nil check here
        call_arg = type_name(call_node.children[2])

        #   nested arrays/symbols for other node shapes), but
        #   parse_receiver_chain re-checks node.is_a?(::Parser::AST::Node)
        #   itself and safely returns nil for anything else
        chain_words = parse_receiver_chain(call_receiver)
        return unless chain_words

        [call_arg, chain_words]
      end

      # @param isa_node [Parser::AST::Node]
      # @return [Array(String, ::Array<String>), nil]
      def parse_isa isa_node
        ISA_METHOD_NAMES.each do |method_name|
          call_type_name, chain_words = parse_call(isa_node, method_name)

          return [call_type_name, chain_words] if call_type_name
        end

        nil
      end

      # @param variable_name [String]
      # @param position [Position]
      #
      # @return [Solargraph::Pin::LocalVariable, Solargraph::Pin::InstanceVariable, nil]
      def find_var variable_name, position
        pins = variable_name.start_with?('@') ? ivars : locals
        # Prefer the pin whose presence starts latest - i.e., the
        # most recent assignment reaching this position - rather
        # than the first-declared pin for this name. Multiple pins
        # can match (e.g. a variable's original declaration and a
        # later reassignment both have presences that include this
        # position), and picking the wrong one here would narrow the
        # stale, superseded pin instead of the current one.
        #
        # Exclude pins whose own assignment is still being evaluated
        # at this position (e.g. the receiver inside its own RHS,
        # such as `baz ||= begin ... end`) - that pin's value isn't
        # available yet, so its presence including this position
        # would otherwise make it a false match ahead of the pin it's
        # about to supersede.
        matches = pins.select do |pin|
          next false unless pin.name == variable_name
          next false unless !pin.presence || pin.presence.include?(position)

          other_loc = Location.new(pin.location&.filename, Range.new(position, position))
          !pin.within_own_assignment?(other_loc)
        end
        matches.max_by { |pin| pin.presence&.start || Position.new(0, 0) }
      end

      # Finds (for a single tracked local/instance variable) or builds
      # (for a chain of simple calls off of one, e.g. ['pin', 'location'],
      # or for a bare/explicit-self 0-arg method call, e.g. ['steps'] from
      # 'steps' or 'self.steps') the pin flow-sensitive-typing facts
      # should be recorded against.
      #
      # A synthesized pin's type is computed lazily, from `node` itself,
      # by Pin::BaseVariable#probe the same way a real local variable's
      # type is computed from its assignment node -- since `node` is the
      # receiver expression at *this*, necessarily earlier, guard site,
      # re-inferring it can never see the narrowing facts this same pin
      # is about to be asked to carry.
      #
      # @param chain_words [::Array<String>]
      # @param node [Parser::AST::Node] the receiver expression, e.g. the
      #   node for 'pin.location'
      # @param position [Position]
      # @return [Solargraph::Pin::LocalVariable, Solargraph::Pin::InstanceVariable, nil]
      def chain_pin chain_words, node, position
        if chain_words.length == 1
          # A bare word is ambiguous from chain_words alone -- 'steps'
          # could be a real local variable (node.type == :lvar) or a
          # 0-arg method call to self (node.type == :send, since the
          # parser only emits :lvar for a name already assigned as a
          # local in this scope). Only the former is a tracked variable.
          # @sg-ignore chain_words is never empty - callers already checked
          return find_var(chain_words.first, position) unless node.is_a?(::Parser::AST::Node) && node.type == :send

          return unless closure

          return self_call_pin(node)
        end

        # @sg-ignore chain_words is never empty - callers already checked
        root_pin = find_var(chain_words.first, position)
        return unless root_pin

        Pin::LocalVariable.new(
          location: Location.from_node(node),
          closure: root_pin.closure,
          name: chain_words.join('.'),
          assignment: node,
          source: :flow_sensitive_typing
        )
      end

      # Builds the synthesized pin for a bare, implicit-self call to a
      # 0-arg method, e.g. 'steps'. Rooted at `closure` rather than at a
      # tracked variable's pin, since there is no variable to inherit a
      # closure from. Named after the bare method word itself (not
      # e.g. 'self.steps') so it lines up with how Chain::Call#resolve
      # looks up a head-position call: by the call's word, via
      # ApiMap#var_at_location.
      #
      # @param node [Parser::AST::Node] the call node, e.g. 'steps'
      # @return [Solargraph::Pin::LocalVariable]
      def self_call_pin node
        Pin::LocalVariable.new(
          location: Location.from_node(node),
          closure: closure,
          name: node.children[1].to_s,
          assignment: node,
          source: :flow_sensitive_typing
        )
      end

      # A true `x.respond_to?(:m)` proves x satisfies the duck type
      # `#m` on the guarded path; ComplexType#narrow_with handles
      # conformance against x's existing type (keeping union arms that
      # provide the method, or the bare duck type for opaque
      # receivers). A false respond_to? is not a sound class-level
      # exclusion (duck conformance isn't class membership), so no
      # false-path fact is asserted.
      #
      # @param rt_node [Parser::AST::Node]
      # @param true_presences [Array<Range>]
      # @param _false_presences [Array<Range>]
      #
      # @return [void]
      def process_respond_to rt_node, true_presences, _false_presences
        return unless rt_node.type == :send && rt_node.children[1] == :respond_to?

        # only a literal-symbol first argument is usable; the optional
        # include_all second argument doesn't change the positive fact
        arg = rt_node.children[2]
        return unless arg&.type == :sym

        # @sg-ignore flow sensitive typing needs to handle attrs
        method_sym = arg.children[0]

        receiver = rt_node.children[0]
        return unless %i[lvar ivar].include?(receiver&.type)

        # @sg-ignore flow sensitive typing needs to handle attrs
        variable_name = receiver.children[0].to_s
        # @sg-ignore Need to add nil check here
        position = Range.from_node(rt_node).start
        pin = find_var(variable_name, position)
        return unless pin

        # @type Hash{Pin::BaseVariable => Array<Hash{Symbol => ComplexType}>}
        if_true = { pin => [{ type: ComplexType.parse("##{method_sym}") }] }
        process_facts(if_true, true_presences)
      end

      # @param isa_node [Parser::AST::Node]
      # @param true_presences [Array<Range>]
      # @param false_presences [Array<Range>]
      #
      # @return [void]
      def process_isa isa_node, true_presences, false_presences
        isa_type_name, chain_words = parse_isa(isa_node)
        return if chain_words.nil? || chain_words.empty?
        # @sg-ignore Need to add nil check here
        isa_position = Range.from_node(isa_node).start

        # @sg-ignore chain_pin's tuple-destructured args typecheck oddly
        pin = chain_pin(chain_words, isa_node.children[0], isa_position)
        return unless pin

        # @type Hash{Pin::BaseVariable => Array<Hash{Symbol => ComplexType}>}
        if_true = {}
        if_true[pin] ||= []
        if_true[pin] << { type: ComplexType.parse(isa_type_name) }
        process_facts(if_true, true_presences)

        # @type Hash{Pin::BaseVariable => Array<Hash{Symbol => ComplexType}>}
        if_false = {}
        if_false[pin] ||= []
        if_false[pin] << { not_type: ComplexType.parse(isa_type_name) }
        process_facts(if_false, false_presences)
      end

      # A true `x.instance_of?(T)` proves x is a T on the guarded path,
      # so the same positive fact `is_a?` asserts applies.
      #
      # The false path is deliberately left alone. `is_a?` can assert
      # `not_type: T` when false, because `!x.is_a?(T)` rules out T and
      # every subclass of T. `instance_of?` compares `x.class` to T by
      # identity, so `!x.instance_of?(T)` is also satisfied by a
      # subclass instance - which is still a T as far as the declared
      # type is concerned. Asserting `not_type: T` there would remove an
      # arm that can still be present, so no false-path fact is
      # recorded.
      #
      # Narrowing to exactly T (excluding subclasses of T) on the true
      # path is a separate, harder problem and is not attempted: the
      # narrowed type may still include a subclass arm, which is a sound
      # upper bound of the real value.
      #
      # @param node [Parser::AST::Node]
      # @param true_presences [Array<Range>]
      # @param _false_presences [Array<Range>]
      #
      # @return [void]
      def process_instance_of node, true_presences, _false_presences
        instance_of_type_name, chain_words = parse_call(node, :instance_of?)
        return if instance_of_type_name.nil? || chain_words.nil? || chain_words.empty?

        # @sg-ignore Need to add nil check here
        position = Range.from_node(node).start

        # @sg-ignore chain_pin's tuple-destructured args typecheck oddly
        pin = chain_pin(chain_words, node.children[0], position)
        return unless pin

        # @type Hash{Pin::BaseVariable => Array<Hash{Symbol => ComplexType}>}
        if_true = { pin => [{ type: ComplexType.parse(instance_of_type_name) }] }
        process_facts(if_true, true_presences)
      end

      # Handles the one case where an `||`-joined pair of conditions
      # can still narrow the true branch: both sides are plain
      # `is_a?` checks on the *same* variable. In that case the
      # variable's type can be narrowed to the union of the two
      # checked types. Any other shape (different variables, or
      # either side not a plain `is_a?` call) is left alone rather
      # than guessing at an unsound narrowing.
      #
      # @param or_node [Parser::AST::Node]
      # @param lhs [Parser::AST::Node]
      # @param rhs [Parser::AST::Node]
      # @param true_ranges [Array<Range>]
      #
      # @return [void]
      def process_or_isa_union or_node, lhs, rhs, true_ranges
        return if true_ranges.empty?

        lhs_type_name, lhs_chain_words = parse_isa(lhs)
        return if lhs_chain_words.nil? || lhs_chain_words.empty?

        rhs_type_name, rhs_chain_words = parse_isa(rhs)
        return if rhs_chain_words.nil? || rhs_chain_words.empty?

        # only sound to narrow when both sides test the same variable
        return unless lhs_chain_words == rhs_chain_words

        # @sg-ignore Need to add nil check here
        or_position = Range.from_node(or_node).start

        # @sg-ignore chain_pin's tuple-destructured args typecheck oddly
        pin = chain_pin(lhs_chain_words, lhs.children[0], or_position)
        return unless pin

        # @type Hash{Pin::BaseVariable => Array<Hash{Symbol => ComplexType}>}
        if_true = {}
        if_true[pin] ||= []
        if_true[pin] << { type: ComplexType.parse(lhs_type_name, rhs_type_name) }
        process_facts(if_true, true_ranges)
      end

      # A true `instance_variable_defined?(:@ivar)` proves `@ivar` has
      # been given some value, even when nothing in this closure's own
      # lexical scope ever assigns it (e.g. a mixin reading an ivar
      # the including class is expected to set). There is no existing
      # pin to narrow in that case - #find_var has nothing to find -
      # so a new pin is synthesized instead, one per guarded presence
      # range, typed as a generic non-nil `Object` and scoped to that
      # range the same way .downcast scopes a narrowed copy of a real
      # pin. Once it exists, #process_respond_to and friends narrow it
      # further via #find_var the same way they narrow any other
      # variable - and outside the guarded presence, #find_var still
      # finds nothing, so an unguarded read of the ivar elsewhere is
      # still correctly reported as unresolved.
      #
      # The false path is left alone: `instance_variable_defined?`
      # returning false only means no assignment has happened yet, not
      # that one can never happen, so there is no fact to assert on
      # the guarded-false branch.
      #
      # Ruby also returns true for an ivar explicitly set to `nil`, so
      # asserting non-nil here is a sound-in-practice approximation,
      # not a proof - the same category of tradeoff #process_instance_of
      # documents for its own true path.
      #
      # @param node [Parser::AST::Node]
      # @param true_presences [Array<Range>]
      # @param _false_presences [Array<Range>]
      #
      # @return [void]
      def process_instance_variable_defined node, true_presences, _false_presences
        return unless node.type == :send && node.children[1] == :instance_variable_defined?
        # only handle the implicit-self form; an explicit receiver
        # isn't the mixin-reads-its-own-ivar shape this exists for
        return unless node.children[0].nil?

        arg = node.children[2]
        return unless arg&.type == :sym

        # @sg-ignore flow sensitive typing needs to handle attrs
        ivar_name = arg.children[0].to_s
        # @sg-ignore flow sensitive typing needs to handle attrs
        return unless ivar_name.start_with?('@')

        # @sg-ignore Need to add nil check here
        position = Range.from_node(node).start
        pin = find_var(ivar_name, position)

        if pin
          # already has a real assignment somewhere in scope; just
          # narrow it like any other guard would
          process_facts({ pin => [{ not_type: ComplexType::NIL }] }, true_presences)
          return
        end

        return if closure.nil?

        true_presences.each do |presence|
          ivars.push(Pin::InstanceVariable.new(
                       name: ivar_name,
                       closure: closure,
                       location: closure.location,
                       return_type: ComplexType.parse('Object'),
                       source: :flow_sensitive_typing,
                       presence: presence
                     ))
        end
      end

      # @param node [Parser::AST::Node, nil]
      # @return [String, nil] YARD/RBS-style literal type tag (e.g., ':foo', '"foo"', '1', 'true')
      def literal_type_name node
        case node&.type
        when :sym
          # @sg-ignore flow sensitive typing needs to handle attrs
          ":#{node.children[0]}"
        when :str
          # @sg-ignore flow sensitive typing needs to handle attrs
          node.children[0].inspect
        when :int
          # @sg-ignore flow sensitive typing needs to handle attrs
          node.children[0].to_s
        when :true # rubocop:disable Lint/BooleanSymbol -- Parser::AST::Node#type for `true` literal
          'true'
        when :false # rubocop:disable Lint/BooleanSymbol -- Parser::AST::Node#type for `false` literal
          'false'
        end
      end

      # @param op_node [Parser::AST::Node]
      # @param method_name [Symbol]
      # @return [Array(String, String), nil] Tuple of literal type name
      #   the variable is being compared against, then the variable name
      def parse_literal_comparison op_node, method_name
        return unless op_node&.type == :send && op_node.children[1] == method_name

        receiver = op_node.children[0]
        arg = op_node.children[2]

        # variable on the left, literal on the right: `foo == :bar`
        if %i[lvar ivar].include?(receiver&.type)
          literal_type = literal_type_name(arg)
          return unless literal_type

          # @sg-ignore flow sensitive typing needs to handle attrs
          [literal_type, receiver.children[0].to_s]
        # literal on the left, variable on the right: `:bar == foo`
        elsif %i[lvar ivar].include?(arg&.type)
          literal_type = literal_type_name(receiver)
          return unless literal_type

          # @sg-ignore flow sensitive typing needs to handle attrs
          [literal_type, arg.children[0].to_s]
        end
      end

      # @param eq_node [Parser::AST::Node]
      # @param true_presences [Array<Range>]
      # @param false_presences [Array<Range>]
      #
      # @return [void]
      def process_eq eq_node, true_presences, false_presences
        literal_type_name, variable_name = parse_literal_comparison(eq_node, :==)
        return if variable_name.nil? || variable_name.empty?

        literal_type = ComplexType.try_parse(literal_type_name)
        return if literal_type.undefined?

        # @sg-ignore Need to add nil check here
        eq_position = Range.from_node(eq_node).start

        pin = find_var(variable_name, eq_position)
        return unless pin

        # @type Hash{Pin::BaseVariable => Array<Hash{Symbol => ComplexType}>}
        if_true = {}
        if_true[pin] ||= []
        if_true[pin] << { type: literal_type }
        process_facts(if_true, true_presences)

        # @type Hash{Pin::BaseVariable => Array<Hash{Symbol => ComplexType}>}
        if_false = {}
        if_false[pin] ||= []
        if_false[pin] << { not_type: literal_type }
        process_facts(if_false, false_presences)
      end

      # @param neq_node [Parser::AST::Node]
      # @param true_presences [Array<Range>]
      # @param false_presences [Array<Range>]
      #
      # @return [void]
      def process_neq neq_node, true_presences, false_presences
        literal_type_name, variable_name = parse_literal_comparison(neq_node, :!=)
        return if variable_name.nil? || variable_name.empty?

        literal_type = ComplexType.try_parse(literal_type_name)
        return if literal_type.undefined?

        # @sg-ignore Need to add nil check here
        neq_position = Range.from_node(neq_node).start

        pin = find_var(variable_name, neq_position)
        return unless pin

        # @type Hash{Pin::BaseVariable => Array<Hash{Symbol => ComplexType}>}
        if_true = {}
        if_true[pin] ||= []
        if_true[pin] << { not_type: literal_type }
        process_facts(if_true, true_presences)

        # @type Hash{Pin::BaseVariable => Array<Hash{Symbol => ComplexType}>}
        if_false = {}
        if_false[pin] ||= []
        if_false[pin] << { type: literal_type }
        process_facts(if_false, false_presences)
      end

      # @param nilp_node [Parser::AST::Node]
      # @return [Array(String, ::Array<String>), nil]
      def parse_nilp nilp_node
        parse_call(nilp_node, :nil?)
      end

      # @param nilp_node [Parser::AST::Node]
      # @param true_presences [Array<Range>]
      # @param false_presences [Array<Range>]
      #
      # @return [void]
      def process_nilp nilp_node, true_presences, false_presences
        nilp_arg, chain_words = parse_nilp(nilp_node)
        return if chain_words.nil? || chain_words.empty?
        # if .nil? got an argument, move on, this isn't the situation
        # we're looking for and typechecking will cover any invalid
        # ones
        return unless nilp_arg.nil?
        # @sg-ignore Need to add nil check here
        nilp_position = Range.from_node(nilp_node).start

        # @sg-ignore chain_pin's tuple-destructured args typecheck oddly
        pin = chain_pin(chain_words, nilp_node.children[0], nilp_position)
        return unless pin

        # @type Hash{Pin::LocalVariable => Array<Hash{Symbol => ComplexType}>}
        if_true = {}
        if_true[pin] ||= []
        if_true[pin] << { type: ComplexType::NIL }
        process_facts(if_true, true_presences)

        # @type Hash{Pin::LocalVariable => Array<Hash{Symbol => ComplexType}>}
        if_false = {}
        if_false[pin] ||= []
        if_false[pin] << { not_type: ComplexType::NIL }
        process_facts(if_false, false_presences)
      end

      # @param bang_node [Parser::AST::Node]
      # @return [Array(String, String), nil]
      def parse_bang bang_node
        parse_call(bang_node, :!)
      end

      # @param bang_node [Parser::AST::Node]
      # @param true_presences [Array<Range>]
      # @param false_presences [Array<Range>]
      #
      # @return [void]
      def process_bang bang_node, true_presences, false_presences
        # pry(main)> require 'parser/current'; Parser::CurrentRuby.parse("!2")
        # => s(:send,
        #   s(:int, 2), :!)
        #       end
        return unless bang_node.type == :send && bang_node.children[1] == :!

        receiver = bang_node.children[0]

        # swap the two presences
        # @sg-ignore Need to add nil check here
        process_expression(receiver, false_presences, true_presences)
      end

      # @param var_node [Parser::AST::Node]
      #
      # @return [String, nil] Variable name referenced
      def parse_variable var_node
        return if var_node.children.length != 1

        var_node.children[0]&.to_s
      end

      # @return [void]
      # @param node [Parser::AST::Node]
      # @param true_presences [Array<Range>]
      # @param false_presences [Array<Range>]
      def process_variable node, true_presences, false_presences
        return unless %i[lvar ivar cvar gvar].include?(node.type)

        variable_name = parse_variable(node)
        return if variable_name.nil?

        # @sg-ignore Need to add nil check here
        var_position = Range.from_node(node).start

        pin = find_var(variable_name, var_position)
        return unless pin

        # @type Hash{Pin::LocalVariable => Array<Hash{Symbol => ComplexType}>}
        if_true = {}
        if_true[pin] ||= []
        if_true[pin] << { not_type: ComplexType::NIL }
        process_facts(if_true, true_presences)

        # @type Hash{Pin::LocalVariable => Array<Hash{Symbol => ComplexType}>}
        if_false = {}
        if_false[pin] ||= []
        if_false[pin] << { type: ComplexType.parse('nil, false') }
        process_facts(if_false, false_presences)
      end

      # Handles a bare truthy check on a call chain, e.g. 'pin.location'
      # in 'return nil unless pin.location', or on a bare, implicit-self
      # 0-arg method call, e.g. 'steps' in 'return nil unless steps'.
      # Bare references to a single local/instance *variable* are
      # handled by #process_variable instead (node.type would be :lvar
      # or :ivar there, not :send, so this never double-processes them).
      #
      # @param node [Parser::AST::Node]
      # @param true_presences [Array<Range>]
      # @param false_presences [Array<Range>]
      #
      # @return [void]
      def process_call_chain node, true_presences, false_presences
        return unless node.type == :send
        # already handled (with inverted true/false semantics) by
        # process_nilp/process_bang
        return if %i[nil? !].include?(node.children[1])

        chain_words = parse_receiver_chain(node)
        return if chain_words.nil? || chain_words.empty?

        # @sg-ignore Need to add nil check here
        position = Range.from_node(node).start

        pin = chain_pin(chain_words, node, position)
        return unless pin

        # @type Hash{Pin::LocalVariable => Array<Hash{Symbol => ComplexType}>}
        if_true = {}
        if_true[pin] ||= []
        if_true[pin] << { not_type: ComplexType::NIL }
        process_facts(if_true, true_presences)

        # @type Hash{Pin::LocalVariable => Array<Hash{Symbol => ComplexType}>}
        if_false = {}
        if_false[pin] ||= []
        if_false[pin] << { type: ComplexType.parse('nil, false') }
        process_facts(if_false, false_presences)
      end

      # @param node [Parser::AST::Node]
      #
      # @return [String, nil]
      def type_name node
        # e.g.,
        #  s(:const, nil, :Baz)
        return unless node&.type == :const
        # @type [Parser::AST::Node, nil]
        module_node = node.children[0]
        # @type [Parser::AST::Node, nil]
        class_node = node.children[1]

        return class_node.to_s if module_node.nil?
        # e.g., ::Baz parses as s(:const, s(:cbase), :Baz) - the
        # leading :cbase marks root-namespace resolution and isn't
        # itself a :const node, so it needs to be recognized here
        # rather than falling into the generic recursive case below.
        return "::#{class_node}" if module_node.type == :cbase

        module_type_name = type_name(module_node)
        return unless module_type_name

        "#{module_type_name}::#{class_node}"
      end

      # @param clause_node [Parser::AST::Node, nil]
      def always_breaks? clause_node
        clause_node&.type == :break
      end

      attr_reader :locals, :ivars, :enclosing_breakable_pin, :enclosing_compound_statement_pin, :closure,
                  :only_downcast_these_names
    end
  end
end
