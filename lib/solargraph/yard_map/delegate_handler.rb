# frozen_string_literal: true

# YARD handler for ActiveSupport's `delegate` macro. Neither plain YARD
# nor `yard-activesupport-concern` recognizes it, so any method defined
# this way (e.g. `Rails::Application#root`, `ActiveJob::Base#queue_adapter`)
# is invisible to completion when it's declared in gem source rather than
# workspace source — `Solargraph::Rails::Delegate` (in the solargraph-rails
# gem) already covers the latter case by walking the local AST directly.
# Loaded via `yardoc -e` from Solargraph::Yardoc.cache, alongside
# `--plugin solargraph`.
module YARD
  module Handlers
    module Ruby
      class DelegateHandler < YARD::Handlers::Ruby::Base
        handles method_call(:delegate)
        namespace_only

        process do
          params = statement.parameters(false).dup
          kwargs = extract_kwargs(params)
          names = validated_attribute_names(params)
          prefix = prefix_for(kwargs)

          names.each do |name|
            meth = prefix ? "#{prefix}_#{name}" : name
            define_delegated_method(meth)
          end
        end

        private

        # `delegate` always defines instance methods, regardless of the
        # `to:` target (an attribute, another method, or `:class`) - the
        # actual argument list is whatever the delegated method accepts, which
        # isn't known statically, so accept anything.
        #
        # @param meth [String]
        # @return [void]
        def define_delegated_method meth
          o = MethodObject.new(namespace, meth, :instance)
          o.parameters = [['*args', nil], ['**kwargs', nil], ['&block', nil]]
          o.signature ||= "def #{meth}(*args, **kwargs, &block)"
          o.source ||= "#{o.signature}\nend"
          register(o)
        end

        # @param kwargs [Hash{Symbol => YARD::Parser::Ruby::AstNode}]
        # @return [String, nil]
        def prefix_for kwargs
          prefix_node = kwargs[:prefix]
          return nil if prefix_node.nil?

          case prefix_node.source.strip
          when 'false' then nil
          when 'true' then symbol_source(kwargs[:to])
          else symbol_source(prefix_node)
          end
        end

        # @param node [YARD::Parser::Ruby::AstNode, nil]
        # @return [String, nil]
        def symbol_source node
          return nil unless node
          node.source.strip.delete_prefix(':')
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
