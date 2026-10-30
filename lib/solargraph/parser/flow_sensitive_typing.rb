# frozen_string_literal: true

module Solargraph
  module Parser
    class FlowSensitiveTyping
      include Solargraph::Parser::NodeMethods

      # Hash methods that return true only when the key is present
      KEY_GUARDS = %i[key? has_key? include? member?].freeze

      # Hash methods that can remove or rename a key, or change how keys
      # match, ending what a key guard proved
      KEY_REMOVERS = %i[
        delete delete_if reject! select! filter! keep_if clear replace shift
        transform_keys! compare_by_identity
      ].freeze

      # String and Array methods without a '!' that change a key in place,
      # so that it may no longer match the entry stored under it
      KEY_MUTATORS = %i[<< []= concat prepend insert replace clear push append unshift setbyte force_encoding].freeze

      # @param locals [Array<Solargraph::Pin::LocalVariable, Solargraph::Pin::KeyLookup>]
      # @param ivars [Array<Solargraph::Pin::InstanceVariable>]
      # @param enclosing_breakable_pin [Solargraph::Pin::Breakable, nil]
      # @param enclosing_compound_statement_pin [Solargraph::Pin::CompoundStatement, nil]
      # @param closure [Solargraph::Pin::Closure, nil] The pin enclosing
      #   the code being processed (e.g. the current method), used to
      #   resolve the declared type of self for narrowing a
      #   self.class == other.class guard (see #process_class_eq).
      def initialize locals, ivars, enclosing_breakable_pin, enclosing_compound_statement_pin, closure = nil
        @locals = locals
        @ivars = ivars
        @enclosing_breakable_pin = enclosing_breakable_pin
        @enclosing_compound_statement_pin = enclosing_compound_statement_pin
        @closure = closure
      end

      # @param and_node [Parser::AST::Node]
      # @param true_ranges [Array<Range>]
      # @param false_ranges [Array<Range>]
      #
      # @return [void]
      def process_and and_node, true_ranges = [], false_ranges = []
        return unless and_node in [:and, ::Parser::AST::Node => lhs, ::Parser::AST::Node => rhs]

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
        return unless or_node in [:or, ::Parser::AST::Node => lhs, ::Parser::AST::Node => rhs]

        before_rhs_loc = rhs.location.expression.adjust(begin_pos: -1)
        before_rhs_pos = Position.new(before_rhs_loc.line, before_rhs_loc.column)

        rhs_presence = Range.new(before_rhs_pos,
                                 get_node_end_position(rhs))

        # can assume if an or is false that every single condition is
        # false, so provide false ranges to assert facts on

        # can't assume if an or is true that every single condition is
        # true, so don't provide true ranges to assert facts on

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
        process_nilp(node, true_presences, false_presences)
        process_bang(node, true_presences, false_presences)
        process_class_eq(node, true_presences, false_presences)
        process_key_guard(node, true_presences)
      end

      # @param if_node [Parser::AST::Node]
      # @param true_ranges [Array<Range>]
      # @param false_ranges [Array<Range>]
      #
      # @return [void]
      def process_if if_node, true_ranges = [], false_ranges = []
        if_node => [:if,
                    ::Parser::AST::Node => conditional_node,
                    ::Parser::AST::Node | nil => then_clause,
                    ::Parser::AST::Node | nil => else_clause]

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

        process_expression(conditional_node, true_ranges, false_ranges)
      end

      # @param while_node [Parser::AST::Node]
      # @param true_ranges [Array<Range>]
      # @param false_ranges [Array<Range>]
      #
      # @return [void]
      def process_while while_node, true_ranges = [], false_ranges = []
        while_node => [:while, ::Parser::AST::Node => conditional_node, ::Parser::AST::Node | nil => do_clause]

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

        unless do_clause.nil?
          #
          # If the condition is true we can assume things about the do clause
          #
          before_do_clause_loc = do_clause.location.expression.adjust(begin_pos: -1)
          before_do_clause_pos = Position.new(before_do_clause_loc.line, before_do_clause_loc.column)
          true_ranges << Range.new(before_do_clause_pos,
                                   get_node_end_position(do_clause))
        end

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
        # @sg-ignore Found after #1259 merged
        return unless %i[lvar ivar].include?(subject_node.type)

        # @sg-ignore Found after #1259 merged
        variable_name = parse_variable(subject_node)
        return if variable_name.nil?

        # @sg-ignore Range.from_node result assumed always present
        subject_position = Range.from_node(subject_node).start
        pin = find_var(variable_name, subject_position)
        return unless pin

        # @sg-ignore node.children[] relies on grammar-guaranteed arity
        when_nodes = case_node.children[1..].compact.select { |child| child.type == :when }
        # @sg-ignore flow sensitive typing needs to narrow down type with an if is_a? check
        when_nodes.each do |when_node|
          # The last child is the body; the rest are the 'when' values
          value_nodes = when_node.children.dup
          body_node = value_nodes.pop
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

      # Narrow a variable subject to the constant each `in` clause
      # matches, over that clause's guard and body:
      #
      #   case x
      #   in Foo   # x is a Foo here
      #   in Bar   # x is a Bar here
      #   end
      #
      # @param case_node [Parser::AST::Node]
      #
      # @return [void]
      def process_case_match case_node
        return unless case_node.type == :case_match

        case_node => [:case_match, ::Parser::AST::Node => subject, *]
        return unless %i[lvar ivar].include?(subject.type)

        pin = find_var(subject.children.fetch(0).to_s, get_node_start_position(subject))
        return unless pin

        # @type [Array<Parser::AST::Node>]
        clauses = case_node.children.drop(1).compact
        clauses.each do |clause|
          next unless clause.type == :in_pattern

          process_in_pattern(pin, clause)
        end
      end

      # The type a variable in locals has wherever an expression is
      # truthy, e.g. `Foo` for `c` in `c.is_a?(Foo)`
      #
      # @param variable [Pin::LocalVariable]
      # @param expression_node [Parser::AST::Node]
      # @param api_map [ApiMap]
      #
      # @return [ComplexType]
      def type_where_true variable, expression_node, api_map
        type = ComplexType.new(variable.typify(api_map).items)
        truthy = Range.from_node(expression_node)
        return type if truthy.nil?

        process_expression(expression_node, [truthy], [])
        # Facts that hold only within part of the expression, like
        # the left side of `a.is_a?(Foo) || a.zero?` on its right
        # side, have other presences
        facts = locals.select { |pin| pin.name == variable.name && pin.presence == truthy }
        facts.each { |pin| type = type.intersect_with(ComplexType.new(pin.typify(api_map).items), api_map) }
        type
      end

      # Records that 'h[k]' is not nil for the rest of the statements
      # after 'h[k] ||= v', as a true 'h.key?(k)' guard does. Chain
      # applies the fact only when 'h' is a Hash whose values can't be
      # nil and the type of 'v' excludes nil.
      #
      # @param or_asgn_node [Parser::AST::Node]
      #
      # @return [void]
      def process_index_or_asgn or_asgn_node
        return unless or_asgn_node.type == :or_asgn

        lookup = or_asgn_node.children[0]
        return unless lookup.is_a?(::Parser::AST::Node) && lookup.type == :send
        return unless lookup.children[1] == :[] && lookup.children.length == 3

        body = enclosing_compound_statement_pin&.node
        parent = body && parent_of(or_asgn_node, body)
        # only statements that follow it in sequence run after it, unlike
        # e.g. what follows 'cond && (h[k] ||= v)'
        return unless parent && %i[begin kwbegin].include?(parent.type)

        presence = Range.new(get_node_end_position(or_asgn_node), get_node_end_position(parent))
        add_key_fact(or_asgn_node, lookup, [presence], value: or_asgn_node.children[1])
      end

      class << self
        include Logging

        # The type of the elements a `select` or `filter` call keeps:
        # the type its block's only parameter has wherever the block
        # body is truthy, e.g. `Foo` for `{ |c| c.is_a?(Foo) }`
        #
        # @param block_body [Parser::AST::Node]
        # @param element_type [ComplexType]
        # @param api_map [ApiMap]
        #
        # @return [ComplexType]
        def narrowed_select_element_type block_body, element_type, api_map
          block_pin = api_map.get_block_pins.find { |pin| block_body_of(pin)&.equal?(block_body) }
          return element_type if block_pin.nil? || block_pin.parameters.length != 1

          param = block_pin.parameters.fetch(0)
          return element_type unless param.arg?

          element = Pin::LocalVariable.new(name: param.name, return_type: element_type, closure: block_pin,
                                           location: param.location, source: :flow_sensitive_typing)
          new([element], [], block_pin, block_pin).type_where_true(element, block_body, api_map)
        end

        private

        # @param block_pin [Pin::Block]
        # @return [Parser::AST::Node, nil]
        def block_body_of block_pin
          return unless block_pin.node in [:block, _call, _args, ::Parser::AST::Node => body]

          body
        end
      end

      include Logging

      private

      # @param pin [Pin::BaseVariable]
      # @param presence [Range]
      # @param downcast_type [ComplexType, nil]
      # @param downcast_not_type [ComplexType, nil]
      #
      # @return [void]
      def add_downcast_var pin, presence:, downcast_type:, downcast_not_type:
        new_pin = pin.downcast(exclude_return_type: downcast_not_type,
                               intersection_return_type: downcast_type,
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

      # @param node [Parser::AST::Node]
      # @param words [::Array<String>] e.g. ['pin', 'location']
      # @param writes [::Array<Position>] start positions found so far
      # @return [void]
      def collect_writes node, words, writes
        range = Range.from_node(node)
        writes << range.start if range && write_to?(node, words)
        node.children.each do |child|
          collect_writes(child, words, writes) if child.is_a?(::Parser::AST::Node)
        end
      end

      # @param node [Parser::AST::Node]
      # @param words [::Array<String>]
      # @return [Boolean]
      def write_to? node, words
        # e.g. 'pin.location ||= x' wraps a reader call in an or_asgn
        wrapped = %i[op_asgn or_asgn and_asgn].include?(node.type)
        target = wrapped ? node.children[0] : node
        return false unless target.is_a?(::Parser::AST::Node)

        variable = target.children[0].to_s
        # an attr_reader on self reads its same-named instance variable
        self_ivar = words.first == 'self' && variable == "@#{words[1]}"
        return variable == words.first || self_ivar if target.type == :ivasgn
        return words.first == variable if %i[lvasgn cvasgn].include?(target.type)
        return false unless target.type == :send

        name = target.children[1].to_s
        return false unless wrapped || name.match?(/\A[a-z_]\w*=\z/i)

        receiver_words = write_receiver(target.children[0], words)
        return false if receiver_words.nil? || receiver_words.length >= words.length

        receiver_words == words.first(receiver_words.length) && name.chomp('=') == words[receiver_words.length]
      end

      # @param node [Parser::AST::Node, nil] a setter's receiver, e.g.
      #   'location' in 'location.filename = x'
      # @param words [::Array<String>] the chain #write_to? checks
      # @return [::Array<String>, nil] the chain `node` reads, e.g. ['pin']
      #   for 'pin', ['self', 'location'] for 'location' or
      #   'self.location', or for '@location' when `words` starts at self
      def write_receiver node, words
        return ['self'] if node.nil? || node.type == :self
        # an attr_reader on self reads its same-named instance variable
        return ['self', node.children[0].to_s.delete_prefix('@')] if node.type == :ivar && words.first == 'self'
        return parse_receiver_chain(node) unless node.type == :send && (node.children[2..] || []).empty?

        base = write_receiver(node.children[0], words)
        base && (base + [node.children[1].to_s])
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
        return [node.children[0].to_s] if %i[lvar ivar cvar].include?(node.type)
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

        base = parse_receiver_chain(receiver)
        return unless base

        base + [method_name.to_s]
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
        process_variable(expression_node, true_ranges, false_ranges)
      end

      # @param call_node [Parser::AST::Node]
      # @param method_name [Symbol]
      # @return [Array(String, String), nil] Tuple of rgument to
      #   function, then receiver of function if it's a variable,
      #   otherwise nil if no simple variable receiver
      def parse_call call_node, method_name
        # Check if conditional node follows this pattern:
        #   s(:send,
        #     s(:send, nil, :foo), :is_a?,
        #     s(:const, nil, :Baz)),
        #
        return unless call_node in [:send, ::Parser::AST::Node | nil => call_receiver, ^method_name, *args]

        call_arg = (args in [::Parser::AST::Node => arg, *]) ? type_name(arg) : nil

        # check if call_receiver looks like this:
        #  s(:send, nil, :foo)
        # and set variable_name to :foo
        if call_receiver in [:send, nil, Symbol => receiver_method, *]
          variable_name = receiver_method.to_s
        end
        # or like this:
        # (lvar :repr)
        if call_receiver in [:lvar | :ivar, Symbol => receiver_variable, *]
          variable_name = receiver_variable.to_s
        end
        return unless variable_name

        [call_arg, variable_name]
      end

      # @param isa_node [Parser::AST::Node]
      # @return [Array(String, String), nil]
      def parse_isa isa_node
        call_type_name, variable_name = parse_call(isa_node, :is_a?)

        return unless call_type_name

        [call_type_name, variable_name]
      end

      # @param variable_name [String]
      # @param position [Position]
      #
      # @sg-ignore https://github.com/castwide/solargraph/pull/1397
      # @return [Solargraph::Pin::LocalVariable, Solargraph::Pin::InstanceVariable, nil]
      def find_var variable_name, position
        if variable_name.start_with?('@')
          # @sg-ignore https://github.com/castwide/solargraph/pull/1258
          ivars.find { |ivar| ivar.name == variable_name && (!ivar.presence || ivar.presence.include?(position)) }
        else
          # @sg-ignore https://github.com/castwide/solargraph/pull/1258
          locals.find { |pin| pin.name == variable_name && (!pin.presence || pin.presence.include?(position)) }
        end
      end

      # @param isa_node [Parser::AST::Node]
      # @param true_presences [Array<Range>]
      # @param false_presences [Array<Range>]
      #
      # @return [void]
      def process_isa isa_node, true_presences, false_presences
        isa_type_name, variable_name = parse_isa(isa_node)
        return if variable_name.nil? || variable_name.empty?
        isa_position = Range.from_node!(isa_node).start

        pin = find_var(variable_name, isa_position)
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

      # @param node [Parser::AST::Node, nil]
      # @return [Parser::AST::Node, nil] the receiver being asked for
      #   its class, e.g. "other" in "other.class", or nil unless
      #   node is exactly a 0-arg .class call
      # @sg-ignore https://github.com/castwide/solargraph/pull/1416
      def parse_class_call node
        return if node.nil?
        return unless node.type == :send && node.children[1] == :class
        return unless (node.children[2..] || []).empty?

        node.children[0]
      end

      # @param node [Parser::AST::Node, nil]
      # @return [String, nil] the plain local/instance variable name
      #   node refers to, or nil unless it is a bare lvar/ivar
      #   reference
      def parse_variable_name node
        return if node.nil?
        return unless %i[lvar ivar].include?(node.type)

        node.children[0].to_s
      end

      # A guard like "self.class == other.class" (or
      # "self.class.eql?(other.class)" or "instance_of?(other.class)")
      # guarantees other has the same runtime class as self. The
      # runtime class of self is always a subtype of the declared
      # instance type of the enclosing method, so the runtime class
      # of other is too -- narrowing other to that declared type is
      # a sound upper bound, the same tradeoff #process_isa
      # documents for is_a?.
      # Only sound when self is an actual instance: a class methods
      # self is the class object itself, whose .class is always
      # ::Class rather than the enclosing type, so scope: :class is
      # left alone.
      #
      # @param node [Parser::AST::Node]
      # @param true_presences [Array<Range>]
      # @param _false_presences [Array<Range>]
      #
      # @return [void]
      def process_class_eq node, true_presences, _false_presences
        return unless node.type == :send && %i[== eql? instance_of?].include?(node.children[1])

        enclosing = closure
        return unless enclosing && enclosing.scope == :instance

        lhs = if node.children[1] == :instance_of?
                # x.instance_of?(y.class) compares x itself; no receiver means self
                node.children[0] || ::Parser::AST::Node.new(:self)
              else
                # @sg-ignore https://github.com/castwide/solargraph/pull/1416
                parse_class_call(node.children[0])
              end
        return unless lhs

        # @sg-ignore https://github.com/castwide/solargraph/pull/1416
        rhs = parse_class_call(node.children[2])
        return unless rhs

        # @sg-ignore https://github.com/castwide/solargraph/pull/1416
        other_side = if lhs.type == :self
                       rhs
                     elsif rhs.type == :self
                       lhs
                     end
        return unless other_side

        self_type = enclosing.context
        return if self_type.undefined?

        # @sg-ignore https://github.com/castwide/solargraph/pull/1416
        variable_name = parse_variable_name(other_side)
        return unless variable_name

        range = Range.from_node(node)
        return unless range

        pin = find_var(variable_name, range.start)
        return unless pin

        if_true = { pin => [{ type: self_type }] }
        process_facts(if_true, true_presences)
      end

      # @param nilp_node [Parser::AST::Node]
      # @return [Array(String, String), nil]
      def parse_nilp nilp_node
        parse_call(nilp_node, :nil?)
      end

      # @param nilp_node [Parser::AST::Node]
      # @param true_presences [Array<Range>]
      # @param false_presences [Array<Range>]
      #
      # @return [void]
      def process_nilp nilp_node, true_presences, false_presences
        nilp_arg, variable_name = parse_nilp(nilp_node)
        return if variable_name.nil? || variable_name.empty?
        # if .nil? got an argument, move on, this isn't the situation
        # we're looking for and typechecking will cover any invalid
        # ones
        return unless nilp_arg.nil?
        nilp_position = Range.from_node!(nilp_node).start

        pin = find_var(variable_name, nilp_position)
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
        return unless bang_node in [:send, ::Parser::AST::Node => receiver, :!, *]

        # swap the two presences
        process_expression(receiver, false_presences, true_presences)
      end

      # @param var_node [Parser::AST::Node]
      #
      # @return [String, nil] Variable name referenced
      def parse_variable var_node
        # only reached for lvar, ivar, cvar and gvar nodes
        var_node => [_, Symbol => variable_name]

        variable_name&.to_s
      end

      # @return [void]
      # @param node [Parser::AST::Node]
      # @param true_presences [Array<Range>]
      # @param false_presences [Array<Range>]
      def process_variable node, true_presences, false_presences
        return unless %i[lvar ivar cvar gvar].include?(node.type)

        variable_name = parse_variable(node)
        return if variable_name.nil?

        var_position = Range.from_node!(node).start

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

      # @param node [Parser::AST::Node, nil]
      #
      # @return [String, nil]
      def type_name node
        # e.g.,
        #  s(:const, nil, :Baz)
        return unless node in [:const, ::Parser::AST::Node | nil => module_node, Symbol => class_node]

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

      # @param pin [Pin::BaseVariable] the case subject
      # @param in_pattern [Parser::AST::Node] (in_pattern PATTERN GUARD BODY)
      #
      # @return [void]
      def process_in_pattern pin, in_pattern
        in_pattern => [:in_pattern, ::Parser::AST::Node => pattern, *]
        type_name = pattern_type_name(pattern)
        # @type [Array<Parser::AST::Node>]
        guard_and_body = in_pattern.children.drop(1).compact
        return if type_name.nil? || guard_and_body.empty?

        before_loc = guard_and_body.fetch(0).location.expression.adjust(begin_pos: -1)
        presence = Range.new(Position.new(before_loc.line, before_loc.column),
                             get_node_end_position(guard_and_body.fetch(-1)))
        process_facts({ pin => [{ type: ComplexType.parse(type_name) }] }, [presence])
      end

      # Records that 'h[k]' is not nil where 'h.key?(k)' is true. A false
      # guard proves nothing about 'h[k]', which a default proc can still
      # answer. Chain applies the fact only when 'h' is a Hash whose values
      # can't be nil, and 'h' and 'k' read variables or attr_readers.
      #
      # @param node [Parser::AST::Node]
      # @param true_presences [Array<Range>]
      #
      # @return [void]
      def process_key_guard node, true_presences
        receiver, method_name, key = node.children
        return unless KEY_GUARDS.include?(method_name) && node.children.length == 3

        # e.g. 'h[k]' with the location of 'h.key?(k)'
        add_key_fact(node, node.updated(nil, [receiver, :[], key]), true_presences)
      end

      # @param location_node [Parser::AST::Node] where the fact is learned
      # @param lookup [Parser::AST::Node] the 'h[k]' the fact is about
      # @param presences [Array<Range>]
      # @param value [Parser::AST::Node, nil] the 'v' in 'h[k] ||= v'
      #
      # @return [void]
      def add_key_fact location_node, lookup, presences, value: nil
        receiver, _, key = lookup.children
        receiver_steps = Pin::KeyLookup.steps_from_node(receiver)
        key_steps = Pin::KeyLookup.key_steps_from_node(key)
        statement = enclosing_compound_statement_pin
        # a method or block body is its own closure
        closure = statement.is_a?(Pin::Closure) ? statement : statement&.closure
        return unless receiver_steps && key_steps && closure

        clip_at_key_writes(presences, receiver, key).each do |presence|
          locals.push Pin::KeyLookup.new(
            location: Location.from_node(location_node),
            closure: closure,
            receiver: receiver_steps,
            key: key_steps,
            presence: presence,
            value: value,
            source: :flow_sensitive_typing
          )
        end
      end

      # @param node [Parser::AST::Node]
      # @param root [Parser::AST::Node]
      # @return [Parser::AST::Node, nil] the node in `root` whose child
      #   is `node`
      def parent_of node, root
        root.children.each do |child|
          next unless child.is_a?(::Parser::AST::Node)
          return root if child.equal?(node)

          found = parent_of(node, child)
          return found if found
        end
        nil
      end

      # Ends each presence of the 'h[k]' fact from a 'h.key?(k)' guard at
      # the first write to 'h' or 'k', e.g. 'h = other', call that can
      # remove a key from 'h', e.g. 'h.delete(k)', or call that can change
      # 'k' in place, e.g. 'k << x'.
      #
      # @param presences [Array<Range>]
      # @param receiver [Parser::AST::Node] e.g. 'h'
      # @param key [Parser::AST::Node] e.g. 'k'
      # @return [Array<Range>]
      def clip_at_key_writes presences, receiver, key
        body = enclosing_compound_statement_pin&.node
        # without the enclosing body, writes can't be ruled out
        return [] if body.nil?

        writes = []
        [receiver, key].each do |node|
          # e.g. ['h'], or ['self', 'table'] for an attr_reader 'table'
          words = write_receiver(node, [])
          collect_writes(body, words, writes) if words
        end
        hash_words = write_receiver(receiver, [])
        # without a name for the receiver, removals can't be ruled out
        return [] if hash_words.nil?

        collect_calls(body, hash_words, writes) { |name| KEY_REMOVERS.include?(name) }
        key_words = write_receiver(key, [])
        if key_words
          collect_calls(body, key_words, writes) { |name| name.end_with?('!') || KEY_MUTATORS.include?(name) }
        end
        presences.map do |presence|
          cut = writes.select { |pos| presence.include?(pos) }.min
          cut ? Range.new(presence.start, cut) : presence
        end
      end

      # Finds calls on a receiver whose method names the block accepts,
      # e.g. 'delete' in 'h.delete(k)'
      #
      # @param node [Parser::AST::Node]
      # @param words [::Array<String>] the receiver, as #write_receiver
      #   names it, e.g. ['self', 'table'] for 'table', 'self.table' or
      #   '@table'
      # @param writes [Array<Position>] start positions found so far
      # @yieldparam name [Symbol] the method called
      # @yieldreturn [Boolean]
      # @return [void]
      def collect_calls node, words, writes, &matches
        if %i[send csend].include?(node.type) && matches.call(node.children[1]) &&
           write_receiver(node.children[0], words) == words
          writes << get_node_start_position(node)
        end
        node.children.each do |child|
          collect_calls(child, words, writes, &matches) if child.is_a?(::Parser::AST::Node)
        end
      end

      # @param clause_node [Parser::AST::Node, nil]
      def always_breaks? clause_node
        clause_node&.type == :break
      end

      attr_reader :locals, :ivars, :enclosing_breakable_pin, :enclosing_compound_statement_pin

      # @return [Solargraph::Pin::Closure, nil]
      attr_reader :closure
    end
  end
end
