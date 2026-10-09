# frozen_string_literal: true

module Solargraph
  module Parser
    module ParserGem
      module NodeProcessors
        class SendNode < Parser::NodeProcessor::Base
          include ParserGem::NodeMethods

          # @type [Hash{Symbol => Class<Pin::Reference>}]
          MIXIN_REFERENCES = {
            include: Pin::Reference::Include,
            extend: Pin::Reference::Extend,
            prepend: Pin::Reference::Prepend
          }.freeze

          # The classes each ActiveSupport lazy load hook runs on, from the
          # +run_load_hooks+ call sites in Rails 7.0 through 8.1.
          #
          # @type [Hash{Symbol => Array<String>}]
          LOAD_HOOK_CLASSES = {
            action_cable_channel: ['ActionCable::Channel::Base'],
            action_cable_channel_test_case: ['ActionCable::Channel::TestCase'],
            action_cable_connection: ['ActionCable::Connection::Base'],
            action_cable_connection_test_case: ['ActionCable::Connection::TestCase'],
            action_cable_test_case: ['ActionCable::TestCase'],
            action_controller: ['ActionController::Base', 'ActionController::API'],
            action_controller_api: ['ActionController::API'],
            action_controller_base: ['ActionController::Base'],
            action_controller_test_case: ['ActionController::TestCase'],
            action_dispatch_integration_test: ['ActionDispatch::IntegrationTest'],
            action_dispatch_request: ['ActionDispatch::Request'],
            action_dispatch_response: ['ActionDispatch::Response'],
            action_dispatch_system_test_case: ['ActionDispatch::SystemTestCase'],
            action_mailbox: ['ActionMailbox::Base'],
            action_mailbox_inbound_email: ['ActionMailbox::InboundEmail'],
            action_mailbox_record: ['ActionMailbox::Record'],
            action_mailbox_test_case: ['ActionMailbox::TestCase'],
            action_mailer: ['ActionMailer::Base'],
            action_mailer_test_case: ['ActionMailer::TestCase'],
            action_text_content: ['ActionText::Content'],
            action_text_encrypted_rich_text: ['ActionText::EncryptedRichText'],
            action_text_record: ['ActionText::Record'],
            action_text_rich_text: ['ActionText::RichText'],
            action_view: ['ActionView::Base'],
            action_view_test_case: ['ActionView::TestCase'],
            active_job: ['ActiveJob::Base'],
            active_job_test_case: ['ActiveJob::TestCase'],
            active_model: ['ActiveModel::Model'],
            active_model_error: ['ActiveModel::Error'],
            active_model_secure_password: ['ActiveModel::SecurePassword'],
            active_model_translation: ['ActiveModel::Translation'],
            active_record: ['ActiveRecord::Base'],
            active_record_database_configurations: ['ActiveRecord::DatabaseConfigurations'],
            active_record_encryption: ['ActiveRecord::Encryption'],
            active_record_fixture_set: ['ActiveRecord::FixtureSet'],
            active_record_mysql2adapter: ['ActiveRecord::ConnectionAdapters::Mysql2Adapter'],
            active_record_postgresqladapter: ['ActiveRecord::ConnectionAdapters::PostgreSQLAdapter'],
            active_record_sqlite3adapter: ['ActiveRecord::ConnectionAdapters::SQLite3Adapter'],
            active_record_trilogyadapter: ['ActiveRecord::ConnectionAdapters::TrilogyAdapter'],
            active_storage_attachment: ['ActiveStorage::Attachment'],
            active_storage_blob: ['ActiveStorage::Blob'],
            active_storage_record: ['ActiveStorage::Record'],
            active_storage_variant_record: ['ActiveStorage::VariantRecord'],
            active_support_test_case: ['ActiveSupport::TestCase'],
            message_pack: ['ActiveSupport::MessagePack']
          }.freeze

          # @type [Array<String>]
          NO_LOAD_HOOK_TARGETS = [].freeze

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
            return process_children if process_load_hook_mixin(method_name)
            if node.children[0].nil?
              if %i[private public protected].include?(method_name)
                process_visibility
              elsif method_name == :module_function
                process_module_function
              elsif %i[attr_reader attr_writer attr_accessor].include?(method_name)
                process_attribute
              elsif method_name == :class_attribute
                process_class_attribute
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
            elsif %i[include extend prepend].include?(method_name) && Parser.is_ast_node?(node.children[0]) && node.children[0].type == :const
              process_qualified_mixin method_name
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

          # @return [void]
          def process_attribute
            # @sg-ignore Need to add nil check here
            node.children[2..].each do |a|
              loc = get_node_location(node)
              clos = region.closure
              cmnt = comments_for(node)
              if %i[attr_reader attr_accessor].include?(node.children[1])
                pins.push Solargraph::Pin::Method.new(
                  location: loc,
                  closure: clos,
                  name: a.children[0].to_s,
                  comments: cmnt,
                  scope: region.scope || :instance,
                  visibility: region.visibility,
                  attribute: true,
                  source: :parser
                )
              end
              next unless %i[attr_writer attr_accessor].include?(node.children[1])
              method_pin = Solargraph::Pin::Method.new(
                location: loc,
                closure: clos,
                name: "#{a.children[0]}=",
                comments: cmnt,
                scope: region.scope || :instance,
                visibility: region.visibility,
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

          # Process an ActiveSupport +class_attribute+ declaration.
          #
          # +class_attribute :name+ generates a singleton reader, writer and
          # predicate plus, unless disabled by options, an instance reader,
          # writer and predicate. The accessors are created at run time, so
          # without pins for them every class that calls +class_attribute+
          # loses its configuration API.
          #
          # @return [void]
          def process_class_attribute
            options = class_attribute_options
            instance_accessor = boolean_option options, 'instance_accessor', true
            instance_reader = boolean_option options, 'instance_reader', instance_accessor
            instance_writer = boolean_option options, 'instance_writer', instance_accessor
            instance_predicate = boolean_option options, 'instance_predicate', true
            node.children[2..].each do |a|
              next unless Parser.is_ast_node?(a) && %i[sym str].include?(a.type)
              name = a.children[0].to_s
              next if name.empty?
              pins.push build_class_attribute_pin name, scope: :class
              pins.push build_class_attribute_pin "#{name}=", scope: :class, writer: true
              pins.push build_class_attribute_pin "#{name}?", scope: :class if instance_predicate
              if instance_reader
                pins.push build_class_attribute_pin name, scope: :instance
                pins.push build_class_attribute_pin "#{name}?", scope: :instance if instance_predicate
              end
              pins.push build_class_attribute_pin "#{name}=", scope: :instance, writer: true if instance_writer
            end
          end

          # The literal keyword arguments passed to a +class_attribute+ call.
          # Values which cannot be evaluated statically are ignored.
          #
          # @return [Hash{String => AST::Node}]
          def class_attribute_options
            hash = node.children[-1]
            return {} unless Parser.is_ast_node?(hash) && hash.type == :hash
            hash.children.each_with_object({}) do |pair, result|
              next unless Parser.is_ast_node?(pair) && pair.type == :pair
              key = pair.children[0]
              next unless Parser.is_ast_node?(key) && %i[sym str].include?(key.type)
              result[key.children[0].to_s] = pair.children[1]
            end
          end

          # @param options [Hash{String => AST::Node}]
          # @param name [String]
          # @param default [Boolean]
          # @return [Boolean]
          def boolean_option options, name, default
            value = options[name]
            return default unless Parser.is_ast_node?(value)
            # rubocop:disable Lint/BooleanSymbol -- these are AST node types
            return true if value.type == :true
            return false if value.type == :false
            # rubocop:enable Lint/BooleanSymbol
            default
          end

          # @param name [String]
          # @param scope [Symbol] :class or :instance
          # @param writer [Boolean]
          # @return [Pin::Method]
          def build_class_attribute_pin name, scope:, writer: false
            pin = Pin::Method.new(
              location: get_node_location(node),
              closure: region.closure,
              name: name,
              comments: comments_for(node),
              scope: scope,
              visibility: region.visibility,
              attribute: true,
              source: :parser
            )
            pin.parameters.push Pin::Parameter.new(name: 'value', decl: :arg, closure: pin, source: :parser) if writer
            pin
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

          # Process mixins called on an explicit receiver, e.g.,
          # +Object.prepend(self)+ in ActiveSupport or
          # +Integer.prepend ActiveSupport::NumericWithFormat+. Without this,
          # gems that extend core classes this way lose every method they
          # share with Object, Module, Integer, etc.
          #
          # @param keyword [::Symbol] one of :include, :extend, :prepend
          # @return [void]
          def process_qualified_mixin keyword
            reference_class = MIXIN_REFERENCES[keyword]
            return if reference_class.nil?
            receiver = node.children[0]
            target = unpack_name(receiver)
            return if target.nil? || target.empty?
            closure = Pin::Namespace.new(location: get_node_location(receiver), name: target, source: :parser)
            node.children[2..].each do |arg|
              next unless Parser.is_ast_node?(arg)
              name = if arg.type == :self
                       region.closure&.full_context&.namespace
                     elsif arg.type == :const
                       unpack_name(arg)
                     end
              next if name.nil? || name.empty?
              pins.push reference_class.new(
                location: get_node_location(arg),
                closure: closure,
                name: name,
                source: :parser
              )
            end
          end

          # Map a mixin inside +ActiveSupport.on_load(:hook) { ... }+ onto the
          # classes that run the hook, e.g. responders' +include
          # ActionController::RespondWith+ onto ActionController::Base.
          #
          # @param method_name [::Symbol]
          # @return [Boolean] whether the call was a mapped mixin
          def process_load_hook_mixin method_name
            targets = load_hook_targets
            return false if targets.empty?
            receiver = node.children[0]
            args = node.children.drop(2)
            if method_name == :send && receiver.nil?
              keyword = args.shift
              return false unless keyword.is_a?(AST::Node) && keyword.type == :sym
              method_name = keyword.children[0]
            elsif !receiver.nil? && !(receiver.is_a?(AST::Node) && receiver.type == :self)
              return false
            end
            reference_class = MIXIN_REFERENCES[method_name]
            return false if reference_class.nil?
            args.each do |arg|
              next unless arg.is_a?(AST::Node) && arg.type == :const
              location = get_node_location(arg)
              targets.each do |target|
                closure = Pin::Namespace.new(location: location, name: target, source: :parser)
                pins.push reference_class.new(location: location, closure: closure, name: unpack_name(arg),
                                              source: :parser)
              end
            end
            true
          end

          # The classes the enclosing +ActiveSupport.on_load+ block runs on.
          #
          # @sg-ignore Hash#fetch(key, default) leaves generic<X> unresolved
          # @return [Array<String>]
          def load_hook_targets
            block = region.closure
            return NO_LOAD_HOOK_TARGETS unless block.is_a?(Pin::Block)
            call = block.receiver
            return NO_LOAD_HOOK_TARGETS unless call.is_a?(AST::Node) && call.type == :send && call.children[1] == :on_load
            owner = call.children[0]
            return NO_LOAD_HOOK_TARGETS unless owner.is_a?(AST::Node) && owner.type == :const
            return NO_LOAD_HOOK_TARGETS unless %w[ActiveSupport ::ActiveSupport].include?(unpack_name(owner))
            hook = call.children[2]
            return NO_LOAD_HOOK_TARGETS unless hook.is_a?(AST::Node) && hook.type == :sym
            LOAD_HOOK_CLASSES.fetch(hook.children[0], NO_LOAD_HOOK_TARGETS)
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
