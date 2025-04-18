# frozen_string_literal: true

module Solargraph
  class Source
    class Chain
      #
      # Handles both method calls and local variable references by
      # first looking for a local with the name 'word', then
      # proceeding to method signature resolution if not found.
      #
      class Call < Chain::Link
        include Solargraph::Parser::NodeMethods

        # @return [String]
        attr_reader :word

        # @return [Location]
        attr_reader :location

        # @return [::Array<Chain>]
        attr_reader :arguments

        # @return [Chain, nil]
        attr_reader :block

        # @param word [String]
        # @param location [Location, nil]
        # @param arguments [::Array<Chain>]
        # @param block [Chain, nil]
        def initialize word, location, arguments = [], block = nil
          @word = word
          @location = location
          @arguments = arguments
          @block = block
          fix_block_pass
        end

        def with_block?
          !!@block
        end

        # @param api_map [ApiMap]
        # @param name_pin [Pin::Closure] name_pin.binder should give us the object on which 'word' will be invoked @see Chain#define
        # @param locals [::Array<Pin::LocalVariable>]
        def resolve api_map, name_pin, locals
          logger.debug { "Call#resolve(name_pin.binder=#{name_pin.binder}, word=#{word}, name_pin=#{name_pin}) - starting" }
          return super_pins(api_map, name_pin) if word == 'super'
          return yield_pins(api_map, name_pin) if word == 'yield'
          found = if head?
            api_map.visible_pins(locals, word, name_pin, location)
          else
            []
          end
          unless found.empty?
            out = inferred_pins(found, api_map, name_pin, locals)
            logger.debug { "Call#resolve(word=#{word}, name_pin=#{name_pin}) - found=#{found} => #{out}" }
            return out
          end
          # @param [ComplexType::UniqueType]
          pins = name_pin.binder.each_unique_type.flat_map do |context|
            method_context = context.namespace == '' ? '' : context.tag
            api_map.get_method_stack(method_context, word, scope: context.scope)
          end
          if pins.empty?
            logger.debug { "Call#resolve(word=#{word}, name_pin=#{name_pin}, name_pin.binder=#{name_pin.binder}) => [] - found no pins for #{word} in #{name_pin.binder}" }
            return []
          end
          out = inferred_pins(pins, api_map, name_pin, locals)
          logger.debug { "Call#resolve(word=#{word}, name_pin=#{name_pin}) - pins=#{pins} => #{out}" }
          out
        end

        def desc
          "#{word}(#{arguments.map(&:desc).join(', ')})"
        end

        include Logging

        private

        # @param pins [::Enumerable<Pin::Method>]
        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base]
        # @param locals [::Array<Pin::LocalVariable>]
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
            sorted_overloads = with_block + without_block
            new_signature_pin = nil
            sorted_overloads.each do |ol|
              next unless ol.arity_matches?(arguments, with_block?)
              match = true

              atypes = []
              arguments.each_with_index do |arg, idx|
                param = ol.parameters[idx]
                if param.nil?
                  match = ol.parameters.any?(&:restarg?)
                  break
                end
                logger.debug { "Call#inferred_pins(word=#{word}, name_pin=#{name_pin}, name_pin.binder=#{name_pin.binder}) - resolving arg #{arg.desc}" }
                atype = atypes[idx] ||= arg.infer(api_map, Pin::ProxyType.anonymous(name_pin.context), locals)
                ptype = param.return_type
                # @todo Weak type comparison
                # unless atype.tag == param.return_type.tag || api_map.super_and_sub?(param.return_type.tag, atype.tag)
                unless ptype.undefined? || atype.name == ptype.name || api_map.super_and_sub?(ptype.name, atype.name) || ptype.generic?
                  match = false
                  break
                end
              end
              if match
                if ol.block && with_block?
                  block_atypes = ol.block.parameters.map(&:return_type)
                  if block.links.map(&:class) == [BlockSymbol]
                    # like the bar in foo(&:bar)
                    blocktype = block_symbol_call_type(api_map, name_pin.context, block_atypes, locals)
                  else
                    blocktype = block_call_type(api_map, name_pin, locals)
                  end
                end
                new_signature_pin = ol.resolve_generics_from_context_until_complete(ol.generics, atypes, nil, nil, blocktype)
                new_return_type = new_signature_pin.return_type
                type = with_params(new_return_type.self_to_type(name_pin.context), name_pin.context).qualify(api_map, name_pin.context.namespace) if new_return_type.defined?
                type ||= ComplexType::UNDEFINED
              end
              break if type.defined?
            end
            p = p.with_single_signature(new_signature_pin) unless new_signature_pin.nil?
            next p.proxy(type) if type.defined?
            if !p.macros.empty?
              result = process_macro(p, api_map, name_pin.context, locals)
              next result unless result.return_type.undefined?
            elsif !p.directives.empty?
              result = process_directive(p, api_map, name_pin.context, locals)
              next result unless result.return_type.undefined?
            end
            p
          end
          out = result.map do |pin|
            if pin.path == 'Class#new' && name_pin.context.tag != 'Class'
              reduced_context = name_pin.context.reduce_class_type
              pin.proxy(reduced_context)
            else
              next pin if pin.return_type.undefined?
              selfy = pin.return_type.self_to_type(name_pin.context)
              selfy == pin.return_type ? pin : pin.proxy(selfy)
            end
          end
          logger.debug { "Call#inferred_pins(pins=#{pins}, name_pin=#{name_pin}) => #{out}" }
          out
        end

        # @param pin [Pin::Base]
        # @param api_map [ApiMap]
        # @param context [ComplexType]
        # @param locals [Enumerable<Pin::Base>]
        # @return [Pin::Base]
        def process_macro pin, api_map, context, locals
          pin.macros.each do |macro|
            # @todo 'Wrong argument type for
            #   Solargraph::Source::Chain::Call#inner_process_macro:
            #   macro expected YARD::Tags::MacroDirective, received
            #   generic<Elem>' is because we lose 'rooted' information
            #   in the 'Chain::Array' class internally, leaving
            #   ::Array#each shadowed when it shouldn't be.
            result = inner_process_macro(pin, macro, api_map, context, locals)
            return result unless result.return_type.undefined?
          end
          Pin::ProxyType.anonymous(ComplexType::UNDEFINED)
        end

        # @param pin [Pin::Method]
        # @param api_map [ApiMap]
        # @param context [ComplexType]
        # @param locals [Enumerable<Pin::Base>]
        # @return [Pin::ProxyType]
        def process_directive pin, api_map, context, locals
          pin.directives.each do |dir|
            macro = api_map.named_macro(dir.tag.name)
            next if macro.nil?
            result = inner_process_macro(pin, macro, api_map, context, locals)
            return result unless result.return_type.undefined?
          end
          Pin::ProxyType.anonymous ComplexType::UNDEFINED
        end

        # @param pin [Pin::Base]
        # @param macro [YARD::Tags::MacroDirective]
        # @param api_map [ApiMap]
        # @param context [ComplexType]
        # @param locals [Enumerable<Pin::Base>]
        # @return [Pin::ProxyType]
        def inner_process_macro pin, macro, api_map, context, locals
          vals = arguments.map{ |c| Pin::ProxyType.anonymous(c.infer(api_map, pin, locals)) }
          txt = macro.tag.text.clone
          if txt.empty? && macro.tag.name
            named = api_map.named_macro(macro.tag.name)
            txt = named.tag.text.clone if named
          end
          i = 1
          vals.each do |v|
            txt.gsub!(/\$#{i}/, v.context.namespace)
            i += 1
          end
          docstring = Solargraph::Source.parse_docstring(txt).to_docstring
          tag = docstring.tag(:return)
          unless tag.nil? || tag.types.nil?
            return Pin::ProxyType.anonymous(ComplexType.try_parse(*tag.types))
          end
          Pin::ProxyType.anonymous(ComplexType::UNDEFINED)
        end

        # @param docstring [YARD::Docstring]
        # @param context [ComplexType]
        # @return [ComplexType, nil]
        def extra_return_type docstring, context
          if docstring.has_tag?('return_single_parameter') #&& context.subtypes.one?
            return context.subtypes.first || ComplexType::UNDEFINED
          elsif docstring.has_tag?('return_value_parameter') && context.value_types.one?
            return context.value_types.first
          end
          nil
        end

        # @param name_pin [Pin::Base]
        # @return [Pin::Method, nil]
        def find_method_pin(name_pin)
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
          pins.reject{|p| p.path == name_pin.path}
        end

        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base]
        # @return [::Array<Pin::Base>]
        def yield_pins api_map, name_pin
          method_pin = find_method_pin(name_pin)
          return [] unless method_pin

          method_pin.signatures.map(&:block).compact.map do |signature_pin|
            return_type = signature_pin.return_type.qualify(api_map, name_pin.namespace)
            signature_pin.proxy(return_type)
          end
        end

        # @param type [ComplexType]
        # @param context [ComplexType]
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
        # @param context [ComplexType]
        # @param block_parameter_types [::Array<ComplexType>]
        # @param locals [::Array<Pin::LocalVariable>]
        # @return [ComplexType, nil]
        def block_symbol_call_type(api_map, context, block_parameter_types, locals)
          # Ruby's shorthand for sending the passed in method name
          # to the first yield parameter with no arguments
          block_symbol_name = block.links.first.word
          block_symbol_call_path = "#{block_parameter_types.first}##{block_symbol_name}"
          callee = api_map.get_path_pins(block_symbol_call_path).first
          return_type = callee&.return_type
          # @todo: Figure out why we get unresolved generics at
          #   this point and need to assume method return types
          #   based on the generic type
          return_type ||= api_map.get_path_pins("#{context.subtypes.first}##{block.links.first.word}").first&.return_type
          return_type || ComplexType::UNDEFINED
        end

        # @param api_map [ApiMap]
        # @return [Pin::Block, nil]
        def find_block_pin(api_map)
          node_location = Solargraph::Location.from_node(block.node)
          return if  node_location.nil?
          block_pins = api_map.get_block_pins
          block_pins.find { |pin| pin.location.contain?(node_location) }
        end

        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base]
        # @param block_parameter_types [::Array<ComplexType>]
        # @param locals [::Array<Pin::LocalVariable>]
        # @return [ComplexType, nil]
        def block_call_type(api_map, name_pin, locals)
          return nil unless with_block?

          block_context_pin = name_pin
          block_pin = find_block_pin(api_map)
          block_context_pin = block_pin.closure if block_pin
          block.infer(api_map, block_context_pin, locals)
        end
      end
    end
  end
end
