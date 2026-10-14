# frozen_string_literal: true

module Solargraph
  module Pin
    class Block < Callable
      include Breakable

      # @return [Parser::AST::Node]
      attr_reader :receiver

      # @return [Parser::AST::Node]
      attr_reader :node

      # @param receiver [Parser::AST::Node, nil]
      # @param node [Parser::AST::Node, nil]
      # @param context [ComplexType, nil]
      # @param args [::Array<Parameter>]
      # @param [Hash{Symbol => Object}] splat
      def initialize receiver: nil, args: [], context: nil, node: nil, **splat
        super(**splat, parameters: args)
        @receiver = receiver
        @context = context
        @return_type = ComplexType.parse('::Proc')
        @node = node
        @name = '<block>'
      end

      # @param api_map [ApiMap]
      # @return [void]
      def rebind api_map
        @rebind ||= maybe_rebind(api_map)
      end

      def binder
        out = @rebind if @rebind&.defined?
        out ||= super
      end

      def context
        @context = @rebind if @rebind&.defined?
        super
      end

      # @param yield_types [::Array<ComplexType>]
      # @param parameters [::Array<Parameter>]
      #
      # @return [::Array<ComplexType>]
      def destructure_yield_types yield_types, parameters
        # yielding a tuple into a block will destructure the tuple
        if yield_types.length == 1
          yield_type = yield_types.first
          return yield_type.all_params if yield_type.tuple? && yield_type.all_params.length == parameters.length
        end
        parameters.map.with_index { |_, idx| yield_types[idx] || ComplexType::UNDEFINED }
      end

      # Whether the yielded types line up with the block's parameters one
      # for one - either a tuple destructured across them, or one yielded
      # type per parameter. When they do not (Ruby auto-splats a single
      # yielded value whose arity we cannot match), the fallback in
      # destructure_yield_types hands position 0 the whole value, which is
      # worse than leaving the parameters undefined.
      #
      # @param yield_types [::Array<ComplexType>]
      # @param parameters [::Array<Parameter>]
      # @return [Boolean]
      def per_position_yield_types? yield_types, parameters
        return true if yield_types.length == parameters.length
        return false unless yield_types.length == 1

        only_type = yield_types.first
        return false if only_type.nil?

        only_type.tuple? && only_type.all_params.length == parameters.length
      end

      # @param api_map [ApiMap]
      # @return [::Array<ComplexType>]
      def typify_parameters api_map
        chain = Parser.chain(receiver, filename, node)
        # @sg-ignore Need to add nil check here
        clip = api_map.clip_at(location.filename, location.range.start)
        locals = clip.locals - [self]
        # @sg-ignore Need to add nil check here
        meths = chain.define(api_map, closure, locals)
        # @type [::Array<ComplexType>, nil]
        partial = nil
        # @todo Convert logic to use signatures
        # @param meth [Pin::Method]
        meths.each do |meth|
          next if meth.block.nil?

          # @sg-ignore flow sensitive typing needs to handle attrs
          yield_types = meth.block.parameters.map(&:return_type)
          # 'arguments' is what the method says it will yield to the
          # block; 'parameters' is what the block accepts
          argument_types = destructure_yield_types(yield_types, parameters)
          param_types = argument_types.each_with_index.map do |arg_type, idx|
            param = parameters[idx]
            param_type = chain.base.infer(api_map, param, locals)
            unless arg_type.nil?
              if arg_type.generic? && param_type.defined?
                # @sg-ignore Need to add nil check here
                namespace_pin = api_map.get_namespace_pins(meth.namespace, closure.namespace).first
                arg_type.resolve_generics(namespace_pin, param_type)
              else
                arg_type.self_to_type(chain.base.infer(api_map, self, locals)).qualify(api_map, *meth.gates)
              end
            end
          end
          return param_types if param_types.all?(&:defined?)

          # remember the best partial result so a single unresolvable
          # yield type (e.g. an unbound generic) doesn't discard the
          # positions that did resolve - but only when the positions
          # actually correspond, never for the auto-splat fallback
          if per_position_yield_types?(yield_types, parameters) && param_types.any? { |t| t&.defined? }
            partial ||= param_types
          end
        end
        partial&.map { |t| t || ComplexType::UNDEFINED } || parameters.map { ComplexType::UNDEFINED }
      end

      private

      # @param api_map [ApiMap]
      # @return [ComplexType]
      def maybe_rebind api_map
        return ComplexType::UNDEFINED unless receiver

        # @sg-ignore Need to add nil check here
        chain = Parser.chain(receiver, location.filename, node)
        # @sg-ignore Need to add nil check here
        locals = api_map.source_map(location.filename).locals_at(location)
        # @sg-ignore Need to add nil check here
        receiver_pin = chain.define(api_map, closure, locals).first
        return ComplexType::UNDEFINED unless receiver_pin

        types = receiver_pin.docstring.tag(:yieldreceiver)&.types
        return ComplexType::UNDEFINED unless types&.any?

        name_pin = self
        # if we have Foo.bar { |x| ... }, and the bar method references self...
        target = if chain.base.defined?
                   # figure out Foo
                   chain.base.infer(api_map, name_pin, locals)
                 else
                   # if not, any self there must be the context of our closure
                   # @sg-ignore Need to add nil check here
                   closure.full_context
                 end

        ComplexType.try_parse(*types).qualify(api_map, *receiver_pin.gates).self_to_type(target)
      end
    end
  end
end
