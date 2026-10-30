# frozen_string_literal: true

module Solargraph
  class Source
    class Chain
      #
      # Handles both method calls and local variable references by
      # first looking for a variable with the name 'word', then
      # proceeding to method signature resolution if not found.
      #
      class Call < Chain::Link
        include Solargraph::Parser::NodeMethods

        # Array#[]/String#[] declare their Range-taking overload
        # nilable, since an out-of-range start returns nil - but a
        # literal 0 (or omitted/beginless) start can never be out of
        # range, so the result is never nil there regardless of the
        # receiver's actual size.
        SLICE_METHOD_PATHS = ['Array#[]', 'String#[]'].freeze
        private_constant :SLICE_METHOD_PATHS

        # Methods that keep the elements their block is truthy for
        SELECTING_METHODS = %w[Array#select Array#filter Enumerable#select Enumerable#filter].freeze

        # @return [String]
        attr_reader :word

        # @return [Location, nil]
        attr_reader :location

        # @return [::Array<Chain>]
        attr_reader :arguments

        # @return [Chain, nil]
        attr_reader :block

        # @param word [String]
        # @param location [Location, nil]
        # @param arguments [::Array<Chain>]
        # @param block [Chain, nil]
        # @param assignment [Boolean] True if the call is written as an
        #   attribute or index assignment (`a.b = c`, `a[b] = c`)
        def initialize word, location = nil, arguments = [], block = nil, assignment: false
          super(word)

          @location = location
          @arguments = arguments
          @block = block
          @assignment = assignment
          fix_block_pass
        end

        def with_block?
          !!@block
        end

        # True if the call is written as an attribute or index
        # assignment, so its value is its last argument
        #
        # @return [Boolean]
        def assignment?
          @assignment
        end

        # @param api_map [ApiMap]
        # @param name_pin [Pin::Closure] name_pin.binder should give us the type of the object on which 'word' will be invoked
        # @param locals [::Array<Pin::LocalVariable>]
        def resolve api_map, name_pin, locals
          return explicit_super_pins(api_map, name_pin) if word == 'super'
          return yield_pins(api_map, name_pin) if word == 'yield'
          found = api_map.var_at_location(locals, word, name_pin, location) if head?

          return inferred_pins([found], api_map, name_pin, locals) unless found.nil?
          binder = name_pin.binder
          # this is a q_call - i.e., foo&.bar - assume result of call
          # will be nil or result as if binder were not nil -
          # chain.rb#maybe_nil will add the nil type later, we just
          # need to worry about the not-nil case

          binder = binder.without_nil if nullable?
          # Resolve one unique type at a time, so a `self` return type narrows to the one that supplied the pin.
          # @type [::Array<Pin::Base>]
          resolved = []
          unresolved_type = false
          binder.each_unique_type do |context|
            if context.bot?
              # bot is a subtype of everything, so a call on it is unreachable code,
              # not unresolved. A DuckMethod pin (bot return type keeps propagating,
              # explicit: false skips arity) gives resolution something to work
              # with; closure must come from name_pin, or #closure raises.
              pin = Pin::DuckMethod.new(name: word, source: :chain, explicit: false, return_type: ComplexType::BOT,
                                        closure: name_pin.closure)
            elsif context.duck_type? && context.name[1..] == word
              # explicit: false skips arity checking; the duck type
              # only tells us the method exists, not its signature
              pin = Pin::DuckMethod.new(name: word, source: :chain, explicit: false)
            else
              ns_tag = context.namespace == '' ? '' : context.namespace_type.tag
              stack = api_map.get_method_stack(ns_tag, word, scope: context.scope)
              pin = stack.first
            end
            if pin.nil?
              unresolved_type = true
              next
            end
            # Bind name_pin to this type alone, so #inferred_pins (incl. Class#new) cannot see the others.
            type_name_pin = Pin::ProxyType.anonymous(name_pin.context,
                                                     closure: name_pin.closure,
                                                     gates: name_pin.gates,
                                                     binder: context,
                                                     source: :chain)
            pins = inferred_pins([pin], api_map, type_name_pin, locals)
            element_type = tuple_element_type(context)
            pins = pins.map { |p| p.proxy(element_type) } unless element_type.nil?
            resolved.concat pins
          end
          return [] if unresolved_type && !api_map.loose_unions
          return [] if resolved.empty?
          # Accumulating every type's result treats the binder as a union, which is the only
          # multi-type binder ComplexType builds; dedup on rooted_tags rather than #tag, which
          # reports only the first member and so collapses two distinct unions.
          resolved.uniq { |pin| [pin.path, pin.return_type.rooted_tags] }
        end

        private

        # @return [Boolean] true if this call's sole argument is a
        #   Range literal with a literal 0 or omitted start
        def zero_start_range_arg?
          return false unless arguments.length == 1

          arg = arguments[0]
          return false if arg.nil?

          node = arg.node
          return false if node.nil?
          return false unless %i[irange erange].include?(node.type)

          start_node = node.children[0]
          return true if start_node.nil?
          # @sg-ignore https://github.com/castwide/solargraph/pull/1416
          return false unless start_node.type == :int

          # @sg-ignore Parser::AST::Node#children is declared Array<Node>, but an :int node's child is a literal Integer
          start_node.children[0].zero?
        end

        # The element a declared tuple returns from #first, #last, or
        # #[] with an integer literal, which Array's signatures can only
        # type as the union of all elements
        #
        # @param context [ComplexType::UniqueType] the receiver
        # @return [ComplexType, nil] nil when this is not such a call
        def tuple_element_type context
          return nil unless context.tuple?
          index = case word
                  when 'first' then 0 if arguments.empty?
                  when 'last' then -1 if arguments.empty?
                  when '[]' then integer_literal_argument
                  end
          return nil if index.nil?
          context.all_params[index] || ComplexType::NIL
        end

        # @return [Integer, nil] the value of the call's only argument,
        #   when that is an integer literal
        def integer_literal_argument
          return nil unless arguments.length == 1
          argument = arguments.first
          return nil if argument.nil? || argument.links.length != 1
          link = argument.links.first
          return nil unless link.is_a?(Chain::Literal)
          value = link.value
          value if value.is_a?(Integer)
        end

        # Checks whether a single overload signature matches the call's
        # arguments/block and, if so, resolves its return type. Threaded
        # through the caller's accumulator so behavior matches the
        # original inline loop: if the overload doesn't match, the
        # incoming type/signature are returned unchanged.
        #
        # @param overload [Pin::Signature]
        # @param pin [Pin::Method]
        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base]
        # @param locals [::Array<Solargraph::Pin::LocalVariable, Solargraph::Pin::Parameter>]
        # @param type [ComplexType]
        # @param new_signature_pin [Pin::Signature, nil]
        # @return [::Array(ComplexType, Pin::Signature)]
        def match_overload_type overload, pin, api_map, name_pin, locals, type, new_signature_pin
          return [type, new_signature_pin] unless overload.arity_matches?(arguments, with_block?)

          match = true
          atypes = []
          arguments.each_with_index do |arg, idx|
            param = overload.parameters[idx]
            match = overload.parameters.any?(&:restarg?) if param.nil?
            break if param.nil?

            arg_name_pin = Pin::ProxyType.anonymous(name_pin.context,
                                                    closure: name_pin.closure,
                                                    gates: name_pin.gates,
                                                    source: :chain)
            # @sg-ignore Array#[] chooses wrong signature when Array has no parameters
            atype = atypes[idx] ||= arg.infer(api_map, arg_name_pin, locals)
            # @sg-ignore Wrong argument type for Solargraph::Pin::Parameter#compatible_arg?: atype expected Solargraph::ComplexType, received Array, Solargraph::ComplexType
            unless param.compatible_arg?(atype, api_map) || param.restarg?
              match = false
              break
            end
          end
          return [type, new_signature_pin] unless match

          if overload.block && with_block?
            # @sg-ignore https://github.com/castwide/solargraph/pull/1258
            block_atypes = overload.block.parameters.map(&:return_type)
            # @todo Need to add nil check here
            blocktype = if block&.links&.map(&:class) == [BlockSymbol]
                          # like the bar in foo(&:bar)
                          block_symbol_call_type(api_map, name_pin.context, block_atypes, locals)
                        else
                          block_call_type(api_map, name_pin, locals)
                        end
          end
          new_signature_pin = overload.resolve_generics_from_context_until_complete(overload.generics, atypes, nil, nil,
                                                                                    blocktype)
          # @todo It shouldn't be necessary to choose either generics or macros
          # @sg-ignore https://github.com/castwide/solargraph/pull/1338
          new_return_type = if new_signature_pin.return_type.defined?
                              # @sg-ignore https://github.com/castwide/solargraph/pull/1338
                              new_signature_pin.return_type
                            else
                              # @sg-ignore Found after #1418 merged
                              named_types = pin.parameter_names.zip(arguments.map { |arg| ComplexType.try_parse(simple_convert(arg.node).to_s) }).to_h
                              pin.typify(api_map).expand(named_types)
                            end
          self_type = if head?
                        # If we're at the head of the chain, we called a
                        # method somewhere that marked itself as returning
                        # self.  Given we didn't invoke this on an object,
                        # this must be a method in this same class - so we
                        # use our own self type
                        name_pin.context
                      else
                        # if we're past the head in the chain, whatever the
                        # type of the lhs side is what 'self' will be in its
                        # declaration - we can't just use the type of the
                        # method pin, as this might be a subclass of the
                        # place where the method is defined
                        name_pin.binder
                      end
          # This same logic applies to the YARD work done by
          # 'with_params()'.
          #
          # qualify(), however, happens in the namespace where
          # the docs were written - from the method pin.
          # @todo Need to add nil check here
          type = if new_return_type.defined?
                   with_params(new_return_type.self_to_type(self_type), self_type).qualify(api_map, *pin.gates)
                 else
                   inferr_from_factory_parameters(api_map, pin)
                 end
          type ||= ComplexType::UNDEFINED
          [type, new_signature_pin]
        end

        # @param pins [::Enumerable<Pin::Base>]
        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base] its #binder resolves `self` in the declarations of `pins`
        # @param locals [::Array<Solargraph::Pin::LocalVariable, Solargraph::Pin::Parameter>]
        # @return [::Array<Pin::Base>]
        def inferred_pins pins, api_map, name_pin, locals
          result = pins.map do |p|
            next p unless p.is_a?(Pin::Method)
            overloads = p.signatures
            # next p if overloads.empty?
            type = ComplexType::UNDEFINED
            # start with overloads that require blocks; if we are
            # passing a block, we want to find a signature that will
            # use it.  If we didn't pass a block, the logic below will
            # reject it regardless

            with_block, without_block = overloads.partition(&:block?)
            # @type [::Array<Pin::Signature>]
            sorted_overloads = with_block + without_block
            # @type [Pin::Signature, nil]
            new_signature_pin = nil
            # @param ol [Pin::Signature]
            sorted_overloads.each do |ol|
              type, new_signature_pin = match_overload_type(ol, p, api_map, name_pin, locals, type, new_signature_pin)
              break if type.defined?
            end
            # RBS types slice args as Range[Integer]; Range has one type
            # parameter shared by both ends, so no overload can match only
            # ranges starting at 0, and the signatures must return nil.
            # Narrow here when the argument is a 0-start Range literal.
            type = type.without_nil if type.nullable? && SLICE_METHOD_PATHS.include?(p.path) && zero_start_range_arg?
            type = narrow_selected(type, p, api_map)
            p = p.with_single_signature(new_signature_pin) unless new_signature_pin.nil?
            next p.proxy(type) if type.defined?
            if !p.macros.empty?
              result = process_macro(p, api_map, name_pin.context, locals)
              # @sg-ignore https://github.com/castwide/solargraph/pull/1338
              next result unless result.return_type.undefined?
            elsif !p.directives.empty?
              result = process_directive(p, api_map, name_pin.context, locals)
              # @sg-ignore https://github.com/castwide/solargraph/pull/1338
              next result unless result.return_type.undefined?
            end
            p
          end
          logger.debug do
            "Call#inferred_pins(name_pin.binder=#{name_pin.binder}, word=#{word}, pins=#{pins.map(&:desc)}, name_pin=#{name_pin}) - result=#{result}"
          end
          result.map do |pin|
            if pin.path == 'Class#new' && name_pin.binder.tag != 'Class'
              reduced_context = name_pin.binder.reduce_class_type
              pin.proxy(reduced_context)
            else
              next pin if pin.return_type.undefined?
              selfy = pin.return_type.self_to_type(name_pin.binder)
              selfy == pin.return_type ? pin : pin.proxy(selfy)
            end
          end
        end

        # @param api_map [ApiMap]
        # @param method_pin [Pin::Method]
        # @return [ComplexType, nil]
        def inferr_from_factory_parameters api_map, method_pin
          factory_parameter = api_map.factory_parameters_for_method(method_pin).find do |factory_param|
            method_pin.parameters.each_with_index.find do |param, index|
              current_argument = arguments[index]
              next if current_argument.nil? || !current_argument.literal?
              last_link = current_argument.links.last
              next unless last_link.is_a?(Chain::Literal)
              argument_value = last_link.value

              param.name == factory_param.param_name && argument_value == factory_param.value
            end
          end

          return nil if factory_parameter.nil?

          factory_parameter.return_type.qualify(api_map, method_pin.namespace)
        end

        # @param pin [Pin::Base]
        # @param api_map [ApiMap]
        # @param context [ComplexType, ComplexType::UniqueType]
        # @param locals [::Array<Solargraph::Pin::LocalVariable, Solargraph::Pin::Parameter>]
        # @return [Pin::Base]
        def process_macro pin, api_map, context, locals
          pin.macros.each do |macro|
            result = inner_process_macro(pin, macro, api_map, context, locals)
            return result unless result.return_type.undefined?
          end
          Pin::ProxyType.anonymous(ComplexType::UNDEFINED, source: :chain)
        end

        # @param pin [Pin::Method]
        # @param api_map [ApiMap]
        # @param context [ComplexType, ComplexType::UniqueType]
        # @param locals [::Array<Solargraph::Pin::LocalVariable, Solargraph::Pin::Parameter>]
        # @return [Pin::ProxyType]
        def process_directive pin, api_map, context, locals
          pin.directives.each do |dir|
            macro = api_map.named_macro(dir.tag.name)
            next if macro.nil?
            result = inner_process_macro(pin, macro, api_map, context, locals)
            return result unless result.return_type.undefined?
          end
          Pin::ProxyType.anonymous ComplexType::UNDEFINED, source: :chain
        end

        # @param pin [Pin::Base]
        # @param macro [YardMap::Macro]
        # @param api_map [ApiMap]
        # @param context [ComplexType, ComplexType::UniqueType]
        # @param locals [::Array<Pin::LocalVariable, Pin::Parameter>]
        # @return [Pin::ProxyType]
        def inner_process_macro pin, macro, api_map, context, locals
          vals = arguments.map { |c| Pin::ProxyType.anonymous(c.infer(api_map, pin, locals), source: :chain) }
          txt = macro.text.clone
          if txt.empty? && macro.tag.name
            named = api_map.named_macro(macro.tag.name)
            txt = named.text.clone if named
          end
          i = 1
          vals.each do |v|
            txt.gsub!(/\$#{i}/, v.context.namespace)
            i += 1
          end
          docstring = Solargraph::Source.parse_docstring(txt).to_docstring
          tag = docstring.tag(:return)
          unless tag.nil? || tag.types.nil?
            return Pin::ProxyType.anonymous(ComplexType.try_parse(*tag.types), source: :chain)
          end
          Pin::ProxyType.anonymous(ComplexType::UNDEFINED, source: :chain)
        end

        # @param docstring [YARD::Docstring]
        # @param context [ComplexType]
        # @return [ComplexType, nil]
        def extra_return_type docstring, context
          if docstring.has_tag?('return_single_parameter') # && context.subtypes.one?
            return context.subtypes.first || ComplexType::UNDEFINED
          elsif docstring.has_tag?('return_value_parameter') && context.value_types.one?
            return context.value_types.first
          end
          nil
        end

        # @param name_pin [Pin::Base]
        # @return [Pin::Method, nil]
        def find_method_pin name_pin
          method_pin = name_pin
          until method_pin.is_a?(Pin::Method)
            # @sg-ignore https://github.com/castwide/solargraph/pull/1338
            method_pin = method_pin.closure
            return if method_pin.nil?
          end
          method_pin
        end

        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base]
        # @return [::Array<Pin::Base>]
        def super_pins api_map, name_pin
          method_pin = find_method_pin(name_pin)
          return [] if method_pin.nil?
          pins = api_map.get_method_stack(method_pin.namespace, method_pin.name, scope: method_pin.context.scope)
          # super dispatches to exactly one method - the nearest ancestor
          # pin, not every ancestor that happens to share the name.
          pins.reject { |p| p.path == method_pin.path }.first(1)
        end

        # Pins for `super(...)` with explicit arguments. Outside a def,
        # it can still call an ancestor's method from a define_method
        # block, which defines a method of the name it is given.
        #
        # Implicit-argument `super` raises a RuntimeError inside
        # define_method, so ZSuper does not use this.
        #
        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base]
        # @return [::Array<Pin::Base>]
        def explicit_super_pins api_map, name_pin
          return super_pins(api_map, name_pin) if find_method_pin(name_pin)

          block_pin = find_define_method_block(name_pin)
          call = define_method_call(block_pin)
          return [] if block_pin.nil? || call.nil?

          name = literal_method_name(call)
          # A computed name could be any method, so its super is untyped
          return [Pin::ProxyType.anonymous(ComplexType::UNDEFINED, source: :chain)] if name.nil?

          namespace = block_pin.namespace
          pins = api_map.get_method_stack(namespace, name, scope: define_method_scope(block_pin))
          pins.reject { |p| p.namespace == namespace }
        end

        # define_method inside `class << self` defines a class method
        #
        # @param pin [Pin::Base, nil] The define_method block or a closure around it
        # @return [Symbol]
        def define_method_scope pin
          return :instance if pin.nil? || pin.is_a?(Pin::Namespace)
          return :class if pin.is_a?(Pin::Singleton)

          define_method_scope(pin.closure)
        end

        # The innermost enclosing block passed to define_method
        #
        # @param name_pin [Pin::Base]
        # @return [Pin::Block, nil]
        def find_define_method_block name_pin
          pin = name_pin
          until pin.nil? || pin.is_a?(Pin::Namespace)
            return pin if pin.is_a?(Pin::Block) && define_method_call(pin)

            pin = pin.closure
          end
          nil
        end

        # The `define_method(name)` call on self that a block is passed to
        #
        # @param block_pin [Pin::Block, nil]
        # @return [Chain::Call, nil]
        def define_method_call block_pin
          return if block_pin.nil?

          receiver_links = Parser.chain(block_pin.receiver).links
          call = receiver_links.last
          return unless call.is_a?(Chain::Call) && call.word == 'define_method' && call.arguments.one?

          call if receiver_links.one? || (receiver_links.length == 2 && receiver_links.first.is_a?(Chain::Head))
        end

        # @param call [Chain::Call] A define_method call
        # @return [String, nil] The defined method's name if it is a literal symbol
        def literal_method_name call
          name_link = call.arguments.first&.links&.last
          return unless name_link.is_a?(Chain::Literal)

          value = name_link.value
          value.to_s if value.is_a?(::Symbol)
        end

        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base]
        # @return [::Array<Pin::Base>]
        def yield_pins api_map, name_pin
          method_pin = find_method_pin(name_pin)
          return [] unless method_pin

          # @param signature_pin [Pin::Signature]
          method_pin.signatures.map(&:block).compact.map do |signature_pin|
            return_type = signature_pin.return_type.qualify(api_map, *name_pin.gates)
            signature_pin.proxy(return_type)
          end
        end

        # @param type [ComplexType, ComplexType::UniqueType]
        # @param context [ComplexType, ComplexType::UniqueType]
        # @return [ComplexType, ComplexType::UniqueType]
        def with_params type, context
          return type unless type.to_s.include?('$')
          ComplexType.try_parse(type.to_s.gsub('$', context.value_types.map(&:rooted_tag).join(', ')).gsub('<>', ''))
        end

        # @return [void]
        def fix_block_pass
          argument = @arguments.last&.links&.first
          @block = @arguments.pop if argument.is_a?(BlockSymbol) || argument.is_a?(BlockVariable)
        end

        # @param api_map [ApiMap]
        # @param context [ComplexType, ComplexType::UniqueType]
        # @param block_parameter_types [::Array<ComplexType>]
        # @param locals [::Array<Pin::LocalVariable>]
        # @return [ComplexType, nil]
        def block_symbol_call_type api_map, context, block_parameter_types, locals
          # Ruby's shorthand for sending the passed in method name
          # to the first yield parameter with no arguments
          block_symbol_link = block&.links&.first
          block_symbol_name = block_symbol_link&.word
          block_symbol_call_path = "#{block_parameter_types.first}##{block_symbol_name}"
          callee = api_map.get_path_pins(block_symbol_call_path).first
          return_type = callee&.return_type
          # @todo: Figure out why we get unresolved generics at
          #   this point and need to assume method return types
          #   based on the generic type
          return_type ||= api_map.get_path_pins("#{context.subtypes.first}##{block_symbol_name}").first&.return_type
          return_type || ComplexType::UNDEFINED
        end

        # @param api_map [ApiMap]
        # @return [Pin::Block, nil]
        def find_block_pin api_map
          node_location = Solargraph::Location.from_node(block&.node)
          return if node_location.nil?
          block_pins = api_map.get_block_pins
          block_pins.find { |pin| pin.location!.contain?(node_location) }
        end

        # Narrow the elements of `select` and `filter` results to the
        # type their block's parameter has where the block is truthy,
        # e.g. `children.select { |c| c.is_a?(Foo) }` is an `Array<Foo>`
        #
        # @param type [ComplexType]
        # @param method_pin [Pin::Method]
        # @param api_map [ApiMap]
        # @return [ComplexType]
        def narrow_selected type, method_pin, api_map
          return type unless SELECTING_METHODS.include?(method_pin.path)
          return type unless type.items.length == 1 && type.rooted_name == '::Array'

          body = block&.node
          return type unless body.is_a?(AST::Node)
          return type if type.all_params.empty?

          element_type = ComplexType.new(type.all_params.flat_map(&:items))
          narrowed = Parser::FlowSensitiveTyping.narrowed_select_element_type(body, element_type, api_map)
          return type if narrowed.undefined?

          array_type = ComplexType::UniqueType.new('Array', [], [narrowed], rooted: true, parameters_type: :list)
          ComplexType.new([array_type])
        end

        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base]
        # @param locals [::Array<Pin::LocalVariable>]
        # @return [ComplexType, nil]
        def block_call_type api_map, name_pin, locals
          return nil unless with_block?

          block_pin = find_block_pin(api_map)
          # We use the block pin as the closure, as the parameters
          # here will only be defined inside the block itself and we
          # need to be able to see them
          # @sg-ignore Wrong argument type for Solargraph::Source::Chain#infer: name_pin expected Solargraph::Pin::Base, received Solargraph::Pin::Block, nil
          block&.infer(api_map, block_pin, locals)
        end

        protected

        def equality_fields
          super + [arguments, block, assignment?]
        end
      end
    end
  end
end
