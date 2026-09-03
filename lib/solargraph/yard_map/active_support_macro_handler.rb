# frozen_string_literal: true

# YARD handler for ActiveSupport's `class_attribute` and `mattr_accessor`
# (and its `cattr_accessor` alias) macros. Neither plain YARD nor the
# `yard-activesupport-concern` plugin recognizes these method calls, so
# every accessor Rails defines through them (e.g.
# `ActiveJob::Base.default_queue_name`, `ActiveRecord::Base.default_role`)
# is otherwise invisible to completion. Loaded via `yardoc -e` from
# Solargraph::Yardoc.cache, alongside `--plugin solargraph`.
module YARD
  module Handlers
    module Ruby
      class ActiveSupportMacroHandler < YARD::Handlers::Ruby::Base
        handles method_call(:class_attribute)
        handles method_call(:mattr_accessor)
        handles method_call(:cattr_accessor)
        namespace_only

        process do
          params = statement.parameters(false).dup
          kwargs = extract_kwargs(params)
          names = validated_attribute_names(params)

          class_attribute = statement.method_name(true) == :class_attribute
          instance_accessor = bool_kwarg(kwargs, :instance_accessor, true)
          instance_reader = bool_kwarg(kwargs, :instance_reader, instance_accessor)
          instance_writer = bool_kwarg(kwargs, :instance_writer, instance_accessor)
          instance_predicate = class_attribute && bool_kwarg(kwargs, :instance_predicate, true)

          names.each do |name|
            define_macro_method(:class, name)
            define_macro_method(:class, "#{name}=", writer: true)
            define_macro_method(:class, "#{name}?") if instance_predicate

            define_macro_method(:instance, name) if instance_reader
            define_macro_method(:instance, "#{name}=", writer: true) if instance_writer
            define_macro_method(:instance, "#{name}?") if instance_predicate && instance_reader
          end
        end

        private

        # @param scope [Symbol] :class or :instance
        # @param meth [String]
        # @param writer [Boolean]
        # @return [void]
        def define_macro_method scope, meth, writer: false
          o = MethodObject.new(namespace, meth, scope)
          if writer
            o.parameters = [['value', nil]]
            o.signature ||= "def #{meth}(value)"
          else
            o.signature ||= "def #{meth}"
          end
          o.source ||= "#{o.signature}\nend"
          register(o)
        end

        # Pulls the trailing keyword-argument list (parsed by Ripper as a
        # bare `:list` of `:assoc` nodes when mixed with positional args) off
        # the end of +params+ and returns it as {Symbol => AstNode}.
        #
        # @param params [Array<YARD::Parser::Ruby::AstNode>]
        # @return [Hash{Symbol => YARD::Parser::Ruby::AstNode}]
        def extract_kwargs params
          return {} if params.empty?

          last = params.last
          return {} unless %i[list bare_assoc_hash hash_literal].include?(last.type)

          params.pop
          hash = {}
          pairs = last.type == :hash_literal ? last[0] : last
          pairs.each do |pair|
            next unless pair.type == :assoc

            key = pair[0].source.sub(/:$/, '')
            hash[key.to_sym] = pair[1]
          end
          hash
        end

        # @param kwargs [Hash{Symbol => YARD::Parser::Ruby::AstNode}]
        # @param key [Symbol]
        # @param default [Boolean]
        # @return [Boolean]
        def bool_kwarg kwargs, key, default
          node = kwargs[key]
          return default if node.nil?

          case node.source.strip
          when 'true' then true
          when 'false' then false
          else default
          end
        end

        # @param params [Array<YARD::Parser::Ruby::AstNode>]
        # @return [Array<String>]
        def validated_attribute_names params
          params.map do |obj|
            case obj.type
            when :symbol_literal
              obj.jump(:ident, :op, :kw, :const).source
            when :string_literal
              obj.jump(:string_content).source
            else
              raise YARD::Parser::UndocumentableError, obj.source
            end
          end
        end
      end
    end
  end
end
