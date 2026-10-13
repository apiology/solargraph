# frozen_string_literal: true

module Solargraph
  module Parser
    module ParserGem
      module NodeProcessors
        class SendNode < Parser::NodeProcessor::Base
          include ParserGem::NodeMethods

          # @sg-ignore @override is adding, not overriding
          def process
            # @sg-ignore Variable type could not be inferred for method_name
            # @type [Symbol]
            method_name = node.children[1]
            # :nocov:
            unless method_name.instance_of?(Symbol)
              Solargraph.assert_or_log(:parser_method_name,
                                       "Expected method name to be a Symbol, got #{method_name.class} for node #{node.inspect}")
              return process_children
            end
            # :nocov:
            sent_kind = sent_attribute_kind if %i[send public_send].include?(method_name)
            if sent_kind
              process_sent_attribute sent_kind
            elsif node.children[0].nil?
              if %i[private public protected].include?(method_name)
                process_visibility
              elsif method_name == :module_function
                process_module_function
              elsif %i[attr_reader attr_writer attr_accessor].include?(method_name)
                process_attribute method_name, node.children[2..] || []
              elsif method_name == :include
                process_include
              elsif method_name == :extend
                process_extend
              elsif method_name == :prepend
                process_prepend
              elsif method_name == :require
                process_require
              elsif method_name == :autoload
                process_autoload
              elsif method_name == :private_constant
                process_private_constant
              elsif method_name == :alias_method && node.children[2] && node.children[2] && node.children[2].type == :sym && node.children[3] && node.children[3].type == :sym
                process_alias_method
              elsif method_name == :private_class_method && node.children[2].is_a?(AST::Node)
                # Processing a private class can potentially handle children on its own
                return if process_private_class_method
              end
            elsif method_name == :require && node.children[0].to_s == '(const nil :Bundler)'
              pins.push Pin::Reference::Require.new(
                Solargraph::Location.new(region.filename,
                                         Solargraph::Range.from_to(0, 0, 0, 0)), 'bundler/require', source: :parser
              )
            end
            process_children
          end

          private

          # @return [void]
          def process_visibility
            if node.children.length > 2
              # @sg-ignore Need to add nil check here
              node.children[2..].each do |child|
                # @sg-ignore Variable type could not be inferred for method_name
                # @type [Symbol]
                visibility = node.children[1]
                # :nocov:
                unless visibility.instance_of?(Symbol)
                  Solargraph.assert_or_log(:parser_visibility,
                                           "Expected visibility name to be a Symbol, got #{visibility.class} for node #{node.inspect}")
                  return process_children
                end
                # :nocov:
                if child.is_a?(::Parser::AST::Node) && %i[sym str].include?(child.type)
                  name = child.children[0].to_s
                  matches = pins.select { |pin| pin.is_a?(Pin::Method) && pin.name == name && pin.namespace == region.closure.full_context.namespace && pin.context.scope == (region.scope || :instance) }
                  matches.each do |pin|
                    # @todo Smelly instance variable access
                    pin.instance_variable_set(:@visibility, visibility)
                  end
                else
                  process_children region.update(visibility: visibility)
                end
              end
            else
              # @todo Smelly instance variable access
              region.instance_variable_set(:@visibility, node.children[1])
            end
          end

          # @param kind [Symbol] :attr_reader, :attr_writer or :attr_accessor
          # @param args [Array<::Parser::AST::Node>] the attribute names
          # @param closure [Pin::Closure]
          # @param scope [Symbol] :class or :instance
          # @param visibility [Symbol]
          # @return [void]
          def process_attribute kind, args, closure: region.closure, scope: region.scope || :instance, visibility: region.visibility
            args.each do |a|
              next unless Parser.is_ast_node?(a) && %i[sym str].include?(a.type)
              loc = get_node_location(node)
              clos = closure
              cmnt = comments_for(node)
              if %i[attr_reader attr_accessor].include?(kind)
                pins.push Solargraph::Pin::Method.new(
                  location: loc,
                  closure: clos,
                  name: a.children[0].to_s,
                  comments: cmnt,
                  scope: scope,
                  visibility: visibility,
                  attribute: true,
                  source: :parser
                )
              end
              next unless %i[attr_writer attr_accessor].include?(kind)
              method_pin = Solargraph::Pin::Method.new(
                location: loc,
                closure: clos,
                name: "#{a.children[0]}=",
                comments: cmnt,
                scope: scope,
                visibility: visibility,
                attribute: true,
                source: :parser
              )
              pins.push method_pin
              method_pin.parameters.push Pin::Parameter.new(name: 'value', decl: :arg, closure: pins.last,
                                                            source: :parser)
              if method_pin.return_type.defined?
                pins.last.docstring.add_tag YARD::Tags::Tag.new(:param, '',
                                                                pins.last.return_type.items.map(&:rooted_tags), 'value')
              end
            end
          end

          # The attribute method named by a +send+ or +public_send+ of
          # +attr_reader+, +attr_writer+ or +attr_accessor+ to an implicit
          # receiver, self or a constant.
          #
          # @return [Symbol, nil]
          def sent_attribute_kind
            receiver = node.children[0]
            return unless receiver.nil? || (receiver.is_a?(AST::Node) && %i[self const].include?(receiver.type))
            sym = node.children[2]
            return unless sym.is_a?(AST::Node) && sym.type == :sym
            kind = sym.children[0]
            kind if kind.is_a?(Symbol) && %i[attr_reader attr_writer attr_accessor].include?(kind)
          end

          # Process e.g. +Rails::Application.send(:attr_accessor, :importmap)+
          # the same way as the equivalent direct call.
          #
          # @param kind [Symbol] :attr_reader, :attr_writer or :attr_accessor
          # @return [void]
          def process_sent_attribute kind
            receiver = node.children[0]
            args = node.children[3..] || []
            if receiver && receiver.type == :const
              target = unpack_name(receiver)
              closure = Pin::Namespace.new(location: get_node_location(receiver), name: target, source: :parser)
              process_attribute kind, args, closure: closure, scope: :instance, visibility: :public
            else
              process_attribute kind, args
            end
          end

          # @return [void]
          def process_include
            return unless node.children[2].is_a?(AST::Node) && node.children[2].type == :const
            cp = region.closure
            # @sg-ignore Need to add nil check here
            node.children[2..].each do |i|
              type = region.scope == :class ? Pin::Reference::Extend : Pin::Reference::Include
              pins.push type.new(
                location: get_node_location(i),
                closure: cp,
                name: unpack_name(i),
                source: :parser
              )
            end
          end

          # @return [void]
          def process_prepend
            return unless node.children[2].is_a?(AST::Node) && node.children[2].type == :const
            cp = region.closure
            # @sg-ignore Need to add nil check here
            node.children[2..].each do |i|
              pins.push Pin::Reference::Prepend.new(
                location: get_node_location(i),
                closure: cp,
                name: unpack_name(i),
                source: :parser
              )
            end
          end

          # @return [void]
          def process_extend
            # @sg-ignore Need to add nil check here
            node.children[2..].each do |i|
              loc = get_node_location(node)
              if i.type == :self
                pins.push Pin::Reference::Extend.new(
                  location: loc,
                  closure: region.closure,
                  name: region.closure.full_context.namespace,
                  source: :parser
                )
              else
                pins.push Pin::Reference::Extend.new(
                  location: loc,
                  closure: region.closure,
                  name: unpack_name(i),
                  source: :parser
                )
              end
            end
          end

          # @return [void]
          def process_require
            return unless node.children[2].is_a?(AST::Node) && node.children[2].type == :str
            path = node.children[2].children[0].to_s
            pins.push Pin::Reference::Require.new(get_node_location(node), path, source: :parser)
          end

          # @return [void]
          def process_autoload
            return unless node.children[3].is_a?(AST::Node) && node.children[3].type == :str
            path = node.children[3].children[0].to_s
            pins.push Pin::Reference::Require.new(get_node_location(node), path, source: :parser)
          end

          # @return [void]
          def process_module_function
            if node.children[2].nil?
              # @todo Smelly instance variable access
              region.instance_variable_set(:@visibility, :module_function)
            elsif %i[sym str].include?(node.children[2].type)
              # @sg-ignore Need to add nil check here
              node.children[2..].each do |x|
                cn = x.children[0].to_s
                # @type [Pin::Method, nil]
                ref = pins.find { |p| p.is_a?(Pin::Method) && p.namespace == region.closure.full_context.namespace && p.name == cn }
                next if ref.nil?
                pins.delete ref
                mm = Solargraph::Pin::Method.new(
                  location: ref.location,
                  closure: ref.closure,
                  name: ref.name,
                  parameters: ref.parameters,
                  comments: ref.comments,
                  scope: :class,
                  visibility: :public,
                  node: ref.node,
                  source: :parser
                )
                cm = Solargraph::Pin::Method.new(
                  location: ref.location,
                  closure: ref.closure,
                  name: ref.name,
                  parameters: ref.parameters,
                  comments: ref.comments,
                  scope: :instance,
                  visibility: :private,
                  node: ref.node,
                  source: :parser
                )
                pins.push mm, cm
                ivars.select { |pin| pin.is_a?(Pin::InstanceVariable) && pin.closure.path == ref.path }.each do |ivar|
                  ivars.delete ivar
                  ivars.push Solargraph::Pin::InstanceVariable.new(
                    location: ivar.location,
                    closure: cm,
                    name: ivar.name,
                    comments: ivar.comments,
                    assignment: ivar.assignment,
                    source: :parser
                  )
                  ivars.push Solargraph::Pin::InstanceVariable.new(
                    location: ivar.location,
                    closure: mm,
                    name: ivar.name,
                    comments: ivar.comments,
                    assignment: ivar.assignment,
                    source: :parser
                  )
                end
              end
            elsif node.children[2].type == :def
              NodeProcessor.process node.children[2], region.update(visibility: :module_function), pins, locals, ivars
            end
          end

          # @return [void]
          def process_private_constant
            return unless node.children[2] && %i[sym str].include?(node.children[2].type)
            cn = node.children[2].children[0].to_s
            ref = pins.select do |p|
              [Solargraph::Pin::Namespace,
               Solargraph::Pin::Constant].include?(p.class) && p.namespace == region.closure.full_context.namespace && p.name == cn
            end.first
            # HACK: Smelly instance variable access
            ref&.instance_variable_set(:@visibility, :private)
          end

          # @return [void]
          def process_alias_method
            get_node_location(node)
            pins.push Solargraph::Pin::MethodAlias.new(
              location: get_node_location(node),
              closure: region.closure,
              name: node.children[2].children[0].to_s,
              original: node.children[3].children[0].to_s,
              scope: region.scope || :instance,
              source: :parser
            )
          end

          # @return [Boolean]
          def process_private_class_method
            if %i[sym str].include?(node.children[2].type)
              ref = pins.select do |p|
                p.is_a?(Pin::Method) && p.namespace == region.closure.full_context.namespace && p.name == node.children[2].children[0].to_s
              end.first
              # HACK: Smelly instance variable access
              ref&.instance_variable_set(:@visibility, :private)
              false
            else
              process_children region.update(scope: :class, visibility: :private)
              true
            end
          end
        end
      end
    end
  end
end
