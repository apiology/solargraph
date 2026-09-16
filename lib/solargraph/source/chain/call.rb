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
        def initialize word, location = nil, arguments = [], block = nil
          super(word)

          @location = location
          @arguments = arguments
          @block = block
          fix_block_pass
        end

        def with_block?
          !!@block
        end

        # @param api_map [ApiMap]
        # @param name_pin [Pin::Closure] name_pin.binder should give us the type of the object on which 'word' will be invoked
        # @param locals [::Array<Pin::LocalVariable>]
        # @param receiver_path [::Array<String>, nil] Dotted-word path of the
        #   receiver chain leading up to this call (see Chain#define). Used
        #   to find flow-sensitive-typing facts recorded against repeated
        #   calls to the same argument-less accessor, e.g. a nil check on
        #   'pin.location' narrowing a later 'pin.location.filename'.
        def resolve api_map, name_pin, locals, receiver_path = nil
          return super_pins(api_map, name_pin) if word == 'super'
          return yield_pins(api_map, name_pin) if word == 'yield'
          found = api_map.var_at_location(locals, word, name_pin, location) if head?
          found ||= narrowed_call_pin(api_map, name_pin, locals, receiver_path) unless head?

          return inferred_pins([found], api_map, name_pin, locals) unless found.nil?
          binder = name_pin.binder
          # this is a q_call - i.e., foo&.bar - assume result of call
          # will be nil or result as if binder were not nil -
          # chain.rb#maybe_nil will add the nil type later, we just
          # need to worry about the not-nil case

          binder = binder.without_nil if nullable?
          # Resolve each arm of a union receiver against that arm alone. A
          # method whose declared return type is `self` must resolve to the
          # arm that supplied the method pin, not to the entire union - e.g.
          # for a String, Symbol receiver, Symbol#to_sym (RBS `-> self`) is
          # Symbol, not String, Symbol.
          top_level_types = binder.is_a?(ComplexType) ? binder.to_a : [binder]
          # @type [::Array<Pin::Base>]
          resolved = []
          unresolved_arm = false
          top_level_types.each do |context|
            arm_pins = method_stack_pins(context, api_map, name_pin, locals)
            if arm_pins.nil?
              unresolved_arm = true
              next
            end
            resolved.concat inferred_pins(arm_pins, api_map, name_pin, locals, context)
          end
          return [] if unresolved_arm && !api_map.loose_unions
          return [] if resolved.empty?
          # Different arms can resolve to the same pin path (a method
          # inherited from a shared ancestor); dedup on the resolved return
          # type too, so a real union doesn't lose every arm but the first.
          resolved.uniq { |pin| [pin.path, pin.return_type.tag] }
        end

        private

        # Looks for a flow-sensitive-typing fact recorded against this
        # exact call chained off of the same receiver expression -- e.g.
        # the narrowing FlowSensitiveTyping records for 'pin.location'
        # after a 'return unless pin.location' guard, consulted here while
        # resolving the 'location' call in a later 'pin.location.filename'.
        #
        # Only applies to simple, argument-less, blockless calls whose
        # entire receiver chain is itself simple -- the same shape
        # FlowSensitiveTyping tracks facts against (see
        # Chain#next_receiver_path).
        #
        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base]
        # @param locals [::Array<Pin::Base>]
        # @param receiver_path [::Array<String>, nil]
        # @return [Pin::Base, nil]
        def narrowed_call_pin api_map, name_pin, locals, receiver_path
          return nil if receiver_path.nil? || receiver_path.empty?
          return nil unless arguments.empty? && !with_block?

          composite_name = (receiver_path + [word]).join('.')
          api_map.var_at_location(locals, composite_name, name_pin, location)
        end

        # Resolves the pins for calling `word` on every top-level
        # alternative of a binder type (loose_unions allows leniency).
        #
        # @param binder_type [ComplexType, ComplexType::UniqueType]
        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base]
        # @param locals [::Array<Pin::LocalVariable, Pin::Parameter>]
        # @return [::Array<Pin::Base>]
        def method_pins_for_binder binder_type, api_map, name_pin, locals
          top_level_types = binder_type.is_a?(ComplexType) ? binder_type.to_a : [binder_type]
          pin_groups = top_level_types.map { |unique_type| method_stack_pins(unique_type, api_map, name_pin, locals) }
          pin_groups = [] if !api_map.loose_unions && pin_groups.any?(&:nil?)
          # Dedup on path *and* return type: alternatives can share a
          # path (e.g. same generic method on different instantiations).
          # @param p [Pin::Base]
          pin_groups.compact.flatten.uniq { |p| [p.path, p.return_type.tag] }
        end

        # Resolves the method stack's first pin for one top-level type.
        # An Intersection needs only one conjunct to define the method.
        #
        # @param unique_type [ComplexType::UniqueType]
        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base]
        # @param locals [::Array<Pin::LocalVariable, Pin::Parameter>]
        # @return [::Array<Pin::Base>, nil] nil when unresolved
        def method_stack_pins unique_type, api_map, name_pin, locals
          if unique_type.is_a?(ComplexType::UniqueType::Intersection)
            resolved = argument_verified_conjuncts(unique_type.conjuncts, api_map, name_pin, locals).filter_map do |conjunct|
              pins = method_pins_for_binder(conjunct, api_map, name_pin, locals)
              pins.empty? ? nil : pins
            end
            return nil if resolved.empty?
            # @param p [Pin::Base]
            resolved.flatten.uniq { |p| [p.path, p.return_type.tag] }
          elsif unique_type.duck_type? && unique_type.name[1..] == word
            # explicit: false skips arity checking; the duck type
            # only tells us the method exists, not its signature
            [Pin::DuckMethod.new(name: word, source: :chain, explicit: false, closure: name_pin.closure)]
          elsif unique_type.bot?
            # bot is a subtype of every type, so any method call on a
            # bot-typed receiver is vacuously valid - the code is
            # unreachable, so there's no real pin to resolve against,
            # but flagging it as "unresolved" would be a false
            # positive. A DuckMethod pin (same one used for `#read`-
            # style duck typing) gives match_overload_type a real
            # Pin::Method to work with - explicit: false skips arity
            # checking - while its return type stays bot, so bot keeps
            # propagating through the rest of the chain instead of
            # being treated as a real value.
            [Pin::DuckMethod.new(name: word, source: :chain, explicit: false, return_type: ComplexType::BOT, closure: name_pin.closure)]
          else
            ns_tag = unique_type.namespace == '' ? '' : unique_type.namespace_type.tag
            visibility = visibility_for(api_map, unique_type, name_pin)
            stack = api_map.get_method_stack(ns_tag, word, scope: unique_type.scope, visibility: visibility)
            return nil if stack.first.nil?
            [stack.first]
          end
        end

        # Which visibilities a call at this position can reach. A
        # receiverless call - head? - reaches private and protected
        # methods whatever self is. A call with an explicit receiver
        # only reaches them from inside the receiver's own namespace or
        # a subclass of it, mirroring ApiMap#get_complex_type_methods.
        #
        # @param api_map [ApiMap]
        # @param context [ComplexType::UniqueType] the receiver's type
        # @param name_pin [Pin::Base]
        # @return [::Array<Symbol>]
        def visibility_for api_map, context, name_pin
          return %i[private protected public] if head?

          from = name_pin.context.namespace
          to = context.namespace
          return %i[private protected public] if to == from || api_map.super_and_sub?(to, from)

          [:public]
        end

        # Narrows conjuncts to the ones with at least one signature the
        # call's actual arguments conform to - the same per-signature
        # overload matching #match_overload_type does, applied per
        # conjunct instead of per signature. Unfiltered if any verdict
        # is unknown (conjunct's method pin/signatures don't resolve).
        #
        # @param conjuncts [::Array<ComplexType>]
        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base]
        # @param locals [::Array<Pin::LocalVariable, Pin::Parameter>]
        # @return [::Array<ComplexType>]
        def argument_verified_conjuncts conjuncts, api_map, name_pin, locals
          return conjuncts if arguments.empty?

          verdicts = conjuncts.map { |c| conjunct_argument_verdict(c, api_map, name_pin, locals) }
          return conjuncts if verdicts.any?(&:nil?)

          matching = conjuncts.zip(verdicts).select { |(_c, matched)| matched }.map(&:first)
          matching.empty? ? conjuncts : matching
        end

        # Whether any of this conjunct's resolved method signatures
        # match the call's actual arguments, or nil if the conjunct's
        # method pin/signatures don't resolve at all.
        #
        # @param conjunct [ComplexType]
        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base]
        # @param locals [::Array<Pin::LocalVariable, Pin::Parameter>]
        # @return [Boolean, nil]
        def conjunct_argument_verdict conjunct, api_map, name_pin, locals
          pins = method_pins_for_binder(conjunct, api_map, name_pin, locals)
          return nil if pins.empty?

          signatures = pins.flat_map(&:signatures)
          return nil if signatures.empty?

          signatures.any? { |s| matching_arg_types(s, api_map, name_pin, locals) }
        end

        # Whether an overload's arity and each parameter's declared
        # type accept the call's actual arguments. Used both for
        # regular overload resolution and, per conjunct, to narrow an
        # Intersection's conjuncts to the ones a call can actually
        # dispatch to (see #conjunct_argument_verdict) - the same
        # question either way: does this signature accept these
        # arguments.
        #
        # @param overload [Pin::Signature]
        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base]
        # @param locals [::Array<Solargraph::Pin::LocalVariable, Solargraph::Pin::Parameter>]
        # @param require_literal [Boolean] see Pin::Parameter#compatible_arg?
        # @return [::Array<ComplexType>, nil] the arguments' inferred types if it matches, nil otherwise
        def matching_arg_types overload, api_map, name_pin, locals, require_literal: true
          return nil unless overload.arity_matches?(arguments, with_block?)

          positional_arguments, keyword_argument = split_keyword_argument(arguments, overload)
          # @type [::Array<ComplexType>]
          atypes = []
          match = positional_arguments_match?(positional_arguments, overload, api_map, name_pin, locals, atypes,
                                              require_literal: require_literal)
          if match
            match &&= keyword_argument_matches?(keyword_argument, overload, api_map, name_pin, locals,
                                                require_literal: require_literal)
          end
          return nil unless match

          atypes
        end

        # A trailing keyword-arguments hash doesn't line up positionally
        # with the method's declared parameters, so it's split off to be
        # matched separately against the keyword/kwrest parameters
        # instead of the positional ones.
        #
        # @param arguments [::Array<Chain>]
        # @param overload [Pin::Signature]
        # @return [::Array(::Array<Chain>, Chain, nil)]
        def split_keyword_argument arguments, overload
          keyword_params = overload.parameters.select { |param| param.keyword? || param.kwrestarg? }
          last_argument = arguments.last
          if !keyword_params.empty? && last_argument.is_a?(Chain) && last_argument.links.last.is_a?(Chain::Hash)
            [arguments[0..-2], last_argument]
          else
            [arguments, nil]
          end
        end

        # @param positional_arguments [::Array<Chain>]
        # @param overload [Pin::Signature]
        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base]
        # @param locals [::Array<Pin::LocalVariable>]
        # @param atypes [::Array<ComplexType>] populated with the inferred type of each positional argument
        # @param require_literal [Boolean] see Pin::Parameter#compatible_arg?
        # @return [Boolean]
        def positional_arguments_match? positional_arguments, overload, api_map, name_pin, locals, atypes, require_literal: true
          positional_params = overload.parameters.reject { |param| param.keyword? || param.kwrestarg? }
          positional_arguments.each_with_index do |arg, idx|
            param = positional_params[idx]
            return positional_params.any?(&:restarg?) if param.nil?

            arg_name_pin = Pin::ProxyType.anonymous(name_pin.context,
                                                    closure: name_pin.closure,
                                                    gates: name_pin.gates,
                                                    source: :chain)
            atype = atypes[idx] ||= arg.infer(api_map, arg_name_pin, locals)
            return false unless param.compatible_arg?(atype, api_map, require_literal: require_literal) || param.restarg?
          end
          true
        end

        # @param keyword_argument [Chain, nil]
        # @param overload [Pin::Signature]
        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base]
        # @param locals [::Array<Pin::LocalVariable>]
        # @param require_literal [Boolean] see Pin::Parameter#compatible_arg?
        # @return [Boolean]
        def keyword_argument_matches? keyword_argument, overload, api_map, name_pin, locals, require_literal: true
          return true if keyword_argument.nil?

          # @type [::Hash{::Symbol => Chain}]
          kwargs = convert_hash(keyword_argument.node)
          keyword_params = overload.parameters.select { |param| param.keyword? || param.kwrestarg? }
          named_params = keyword_params.reject(&:kwrestarg?)
          kwrestarg = keyword_params.find(&:kwrestarg?)

          kw_arg_name_pin = Pin::ProxyType.anonymous(name_pin.context,
                                                     closure: name_pin.closure,
                                                     gates: name_pin.gates,
                                                     source: :chain)
          kwargs.each_pair do |key, value_chain|
            param = named_params.find { |p| p.name.to_sym == key }
            if param.nil?
              return false if kwrestarg.nil?
              next
            end
            atype = value_chain.infer(api_map, kw_arg_name_pin, locals)
            return false unless param.compatible_arg?(atype, api_map, require_literal: require_literal)
          end
          named_params.none? { |param| param.decl == :kwarg && !kwargs.key?(param.name.to_sym) }
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
        # @param self_binder [ComplexType, ComplexType::UniqueType] The type that
        #   `self` refers to in the overload's declaration. For a union receiver
        #   this is the single arm which supplied `pin`, not the whole union.
        # @param require_literal [Boolean] see Pin::Parameter#compatible_arg?
        # @return [::Array(ComplexType, Pin::Signature)]
        def match_overload_type overload, pin, api_map, name_pin, locals, type, new_signature_pin, self_binder:,
                                require_literal: true
          atypes = matching_arg_types(overload, api_map, name_pin, locals, require_literal: require_literal)
          return [type, new_signature_pin] if atypes.nil?

          if overload.block && with_block?
            block_atypes = overload.block.parameters.map(&:return_type)
            # @todo Need to add nil check here
            # @sg-ignore Need to add nil check here
            blocktype = if block.links.map(&:class) == [BlockSymbol]
                          # like the bar in foo(&:bar)
                          block_symbol_call_type(api_map, name_pin.context, block_atypes, locals)
                        else
                          block_call_type(api_map, name_pin, locals)
                        end
          end
          new_signature_pin = overload.resolve_generics_from_context_until_complete(overload.generics, atypes, nil, nil,
                                                                                    blocktype)
          # @todo It shouldn't be necessary to choose either generics or macros
          # @sg-ignore Need to add nil check here
          new_return_type = if new_signature_pin.return_type.defined?
                              new_signature_pin.return_type
                            else
                              # @sg-ignore Need to add nil check here
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
                        self_binder
                      end
          # This same logic applies to the YARD work done by
          # 'with_params()'.
          #
          # qualify(), however, happens in the namespace where
          # the docs were written - from the method pin.
          # @todo Need to add nil check here
          # @sg-ignore Need to add nil check here
          if new_return_type.defined?
            # @sg-ignore Need to add nil check here
            type = with_params(new_return_type.self_to_type(self_type), self_type).qualify(api_map, *pin.gates)
          end
          type ||= ComplexType::UNDEFINED
          [type, new_signature_pin]
        end

        # @param pins [::Enumerable<Pin::Base>]
        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base]
        # @param locals [::Array<Solargraph::Pin::LocalVariable, Solargraph::Pin::Parameter>]
        # @param self_binder [ComplexType, ComplexType::UniqueType, nil] The
        #   type that `self` refers to in the resolved pins' declarations. For a
        #   union receiver this is the single arm which supplied `pins`, not the
        #   whole union.
        # @return [::Array<Pin::Base>]
        def inferred_pins pins, api_map, name_pin, locals, self_binder = nil
          self_binder ||= name_pin.binder
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
            # A signature whose block declares no yielded parameters
            # (e.g. a `&block` parameter documented with no @yieldparam,
            # which yields `{ () -> }`) says nothing about what the block
            # receives. When a sibling signature declares yielded
            # parameters, try that one first: the block's parameters
            # resolve from whichever signature is selected here, and Ruby
            # blocks accept fewer arguments than are yielded, so the
            # parameterized signature is the strictly more informative
            # match whenever both are otherwise equally applicable.
            yielding, non_yielding = with_block.partition { |sig| !sig.block.parameters.empty? }
            # @sg-ignore flow sensitive typing should handle is_a? and next
            # @type Array<Pin::Signature>
            sorted_overloads = yielding + non_yielding + without_block
            # @type [Pin::Signature, nil]
            new_signature_pin = nil
            # @type [Pin::Signature, nil]
            selected_signature_pin = nil
            # Two passes: first require an exact-literal match on any
            # literal-typed overload parameter (so a real sibling
            # catch-all, e.g. tuple's non-literal fallback, wins over a
            # literal overload for a non-literal argument). If nothing
            # matches at all, retry without that requirement - a
            # literal-typed parameter with no non-literal sibling
            # overload (e.g. Hash#fetch's key resolved to a literal
            # from the receiver's declared type) would otherwise reject
            # every candidate and fall through to the union of all
            # overloads' return types instead of the one real match.
            [true, false].each do |require_literal|
              break if type.defined?
              # @sg-ignore flow sensitive typing should handle is_a? and next
              # @param ol [Pin::Signature]
              sorted_overloads.each do |ol|
                type, new_signature_pin = match_overload_type(ol, p, api_map, name_pin, locals, type, new_signature_pin,
                                                              self_binder: self_binder,
                                                              require_literal: require_literal)
                # Signatures are tried in preference order, so the first to
                # match is the best available match. A later one may replace
                # it only by supplying the return type it could not.
                selected_signature_pin = new_signature_pin if selected_signature_pin.nil? || type.defined?
                break if type.defined?
              end
            end
            p = p.with_single_signature(selected_signature_pin) unless selected_signature_pin.nil?
            next p.proxy(type) if type.defined?
            if !p.macros.empty?
              macro_pin = process_macro(p, api_map, name_pin.context, locals)
              next macro_pin unless macro_pin.return_type.undefined?
            elsif !p.directives.empty?
              directive_pin = process_directive(p, api_map, name_pin.context, locals)
              next directive_pin unless directive_pin.return_type.undefined?
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
              # @sg-ignore Need to add nil check here
              next pin if pin.return_type.undefined?
              # @sg-ignore Need to add nil check here
              selfy = pin.return_type.self_to_type(self_binder)
              # @sg-ignore Need to add nil check here
              selfy == pin.return_type ? pin : pin.proxy(selfy)
            end
          end
        end

        # @param pin [Pin::Base]
        # @param api_map [ApiMap]
        # @param context [ComplexType, ComplexType::UniqueType]
        # @param locals [::Array<Solargraph::Pin::LocalVariable, Solargraph::Pin::Parameter>]
        # @return [Pin::Base]
        def process_macro pin, api_map, context, locals
          pin.macros.each do |macro|
            # @todo 'Wrong argument type for
            #   Solargraph::Source::Chain::Call#inner_process_macro:
            #   macro expected YARD::Tags::MacroDirective, received
            #   generic<Elem>' is because we lose 'rooted' information
            #   in the 'Chain::Array' class internally, leaving
            #   ::Array#each shadowed when it shouldn't be.
            # @sg-ignore macro is Solargraph::YardMap::Macro, wraps a YARD::Tags::MacroDirective
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
            # @sg-ignore macro is Solargraph::YardMap::Macro, wraps a YARD::Tags::MacroDirective
            result = inner_process_macro(pin, macro, api_map, context, locals)
            return result unless result.return_type.undefined?
          end
          Pin::ProxyType.anonymous ComplexType::UNDEFINED, source: :chain
        end

        # @param pin [Pin::Base]
        # @param macro [YARD::Tags::MacroDirective]
        # @param api_map [ApiMap]
        # @param context [ComplexType, ComplexType::UniqueType]
        # @param locals [::Array<Pin::LocalVariable, Pin::Parameter>]
        # @return [Pin::ProxyType]
        def inner_process_macro pin, macro, api_map, context, locals
          vals = arguments.map { |c| Pin::ProxyType.anonymous(c.infer(api_map, pin, locals), source: :chain) }
          txt = macro.tag.text.clone
          # @sg-ignore Need to add nil check here
          if txt.empty? && macro.tag.name
            named = api_map.named_macro(macro.tag.name)
            txt = named.tag.text.clone if named
          end
          i = 1
          vals.each do |v|
            # @sg-ignore Need to add nil check here
            txt.gsub!(/\$#{i}/, v.context.namespace)
            i += 1
          end
          # @sg-ignore Need to add nil check here
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
          pins.reject { |p| p.path == name_pin.path }
        end

        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base]
        # @return [::Array<Pin::Base>]
        def yield_pins api_map, name_pin
          method_pin = find_method_pin(name_pin)
          return [] unless method_pin

          # @param signature_pin [Pin::Signature]
          method_pin.signatures.map(&:block).compact.map do |signature_pin|
            # @sg-ignore Need to add nil check here
            return_type = signature_pin.return_type.qualify(api_map, *name_pin.gates)
            signature_pin.proxy(return_type)
          end
        end

        # @param type [ComplexType]
        # @param context [ComplexType, ComplexType::UniqueType]
        # @return [ComplexType]
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
          # @sg-ignore Need to add nil check here
          block_symbol_name = block.links.first.word
          block_symbol_call_path = "#{block_parameter_types.first}##{block_symbol_name}"
          callee = api_map.get_path_pins(block_symbol_call_path).first
          return_type = callee&.return_type
          # @todo: Figure out why we get unresolved generics at
          #   this point and need to assume method return types
          #   based on the generic type
          # @sg-ignore Need to add nil check here
          return_type ||= api_map.get_path_pins("#{context.subtypes.first}##{block.links.first.word}").first&.return_type
          return_type || ComplexType::UNDEFINED
        end

        # @param api_map [ApiMap]
        # @return [Pin::Block, nil]
        def find_block_pin api_map
          # @sg-ignore Need to add nil check here
          node_location = Solargraph::Location.from_node(block.node)
          return if node_location.nil?
          block_pins = api_map.get_block_pins
          # @sg-ignore Need to add nil check here
          block_pins.find { |pin| pin.location.contain?(node_location) }
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
          # @sg-ignore Need to add nil check here
          block.infer(api_map, block_pin, locals)
        end

        protected

        def equality_fields
          super + [arguments, block]
        end
      end
    end
  end
end
