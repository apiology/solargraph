# frozen_string_literal: true

describe Solargraph::Parser::ParserGem::NodeProcessors::SendNode do
  # @param namespace [String]
  # @param code [String]
  # @return [Array<Solargraph::Pin::Method>]
  def method_pins_for namespace, code
    Solargraph::SourceMap.load_string(code).pins.select do |pin|
      pin.is_a?(Solargraph::Pin::Method) && pin.namespace == namespace
    end
  end

  # @return [Array<Array(String, Symbol)>]
  def accessors pins
    pins.map { |pin| [pin.name, pin.context.scope] }.sort
  end

  it 'generates accessors for class_attribute' do
    pins = method_pins_for 'Foo', %(
      class Foo
        class_attribute :bar
      end
    )
    expect(accessors(pins)).to eq([
                                    ['bar', :class],
                                    ['bar', :instance],
                                    ['bar=', :class],
                                    ['bar=', :instance],
                                    ['bar?', :class],
                                    ['bar?', :instance]
                                  ])
  end

  it 'generates accessors for multiple attributes' do
    pins = method_pins_for 'Foo', %(
      class Foo
        class_attribute :bar, :baz
      end
    )
    expect(pins.count { |pin| pin.name.start_with?('bar') }).to eq(6)
    expect(pins.count { |pin| pin.name.start_with?('baz') }).to eq(6)
  end

  it 'omits instance accessors when instance_accessor is false' do
    pins = method_pins_for 'Foo', %(
      class Foo
        class_attribute :bar, instance_accessor: false
      end
    )
    expect(accessors(pins)).to eq([
                                    ['bar', :class],
                                    ['bar=', :class],
                                    ['bar?', :class]
                                  ])
  end

  it 'omits instance writers when instance_writer is false' do
    pins = method_pins_for 'Foo', %(
      class Foo
        class_attribute :bar, instance_writer: false
      end
    )
    expect(accessors(pins)).to eq([
                                    ['bar', :class],
                                    ['bar', :instance],
                                    ['bar=', :class],
                                    ['bar?', :class],
                                    ['bar?', :instance]
                                  ])
  end

  it 'omits predicates when instance_predicate is false' do
    pins = method_pins_for 'Foo', %(
      class Foo
        class_attribute :bar, instance_predicate: false
      end
    )
    expect(accessors(pins)).to eq([
                                    ['bar', :class],
                                    ['bar', :instance],
                                    ['bar=', :class],
                                    ['bar=', :instance]
                                  ])
  end

  it 'marks generated accessors as attributes' do
    pins = method_pins_for 'Foo', %(
      class Foo
        class_attribute :bar
      end
    )
    expect(pins.all?(&:attribute?)).to be(true)
  end

  it 'gives class attribute writers a single parameter' do
    pins = method_pins_for 'Foo', %(
      class Foo
        class_attribute :bar
      end
    )
    writers = pins.select { |pin| pin.name == 'bar=' }
    expect(writers.size).to eq(2)
    expect(writers.all? { |pin| pin.parameters.map(&:name) == ['value'] }).to be(true)
  end

  it 'maps a prepend with an explicit receiver' do
    map = Solargraph::SourceMap.load_string %(
      module Mixin
        def helper; end

        String.prepend(self)
      end
    )
    refs = map.pins.select { |pin| pin.is_a?(Solargraph::Pin::Reference::Prepend) }
    expect(refs.map { |ref| [ref.namespace, ref.name] }).to include(%w[String Mixin])
  end

  it 'maps an include with an explicit receiver' do
    map = Solargraph::SourceMap.load_string %(
      module Mixin
      end

      Integer.include Mixin
    )
    refs = map.pins.select { |pin| pin.is_a?(Solargraph::Pin::Reference::Include) }
    expect(refs.map { |ref| [ref.namespace, ref.name] }).to include(%w[Integer Mixin])
  end

  it 'exposes methods from a module prepended onto another class' do
    api_map = Solargraph::ApiMap.new
    source = Solargraph::Source.load_string(%(
      module Mixin
        def helper; end

        String.prepend(self)
      end
    ), 'test.rb')
    api_map.map source
    methods = api_map.get_methods('String', scope: :instance)
    expect(methods.map(&:name)).to include('helper')
  end

  # @param code [String]
  # @return [Array<Array(String, String, String)>]
  def mixins_for code
    Solargraph::SourceMap.load_string(code).pins.select { |pin| pin.is_a?(Solargraph::Pin::Reference) }
                         .reject { |pin| pin.is_a?(Solargraph::Pin::Reference::Require) }
                         .map { |pin| [pin.class.name.split('::').last, pin.namespace, pin.name] }
  end

  context 'with ActiveSupport.on_load and no convention supplying hook targets' do
    it 'maps nothing' do
      refs = mixins_for %(
        ActiveSupport.on_load(:active_record) do
          include Mixin
        end
      )
      expect(refs).to eq([['Include', '', 'Mixin']])
    end
  end

  context 'with ActiveSupport.on_load' do
    let(:hook_convention) do
      Class.new(Solargraph::Convention::Base) do
        def load_hook_targets
          {
            active_record: ['ActiveRecord::Base'],
            action_view: ['ActionView::Base'],
            action_controller: ['ActionController::Base', 'ActionController::API'],
            action_controller_base: ['ActionController::Base'],
            my_hook: ['My::Klass']
          }
        end
      end
    end

    before { Solargraph::Convention.register hook_convention }

    after { Solargraph::Convention.unregister hook_convention }

    it 'maps a hook a convention supplies' do
      refs = mixins_for %(
        ActiveSupport.on_load(:my_hook) do
          include Mixin
        end
      )
      expect(refs).to eq([%w[Include My::Klass Mixin]])
    end

    it 'maps include onto the class the hook loads' do
      refs = mixins_for %(
        ActiveSupport.on_load(:active_record) do
          include Mixin
        end
      )
      expect(refs).to eq([%w[Include ActiveRecord::Base Mixin]])
    end

    it 'maps extend and prepend onto the class the hook loads' do
      refs = mixins_for %(
        ::ActiveSupport.on_load(:action_view) do
          extend Mixin
          prepend Other
        end
      )
      expect(refs).to eq([%w[Extend ActionView::Base Mixin], %w[Prepend ActionView::Base Other]])
    end

    it 'maps every module in one include' do
      refs = mixins_for %(
        ActiveSupport.on_load(:action_controller_base) do
          include First, Second
        end
      )
      expect(refs).to eq([%w[Include ActionController::Base First], %w[Include ActionController::Base Second]])
    end

    it 'maps a hook that runs on several classes onto each of them' do
      refs = mixins_for %(
        ActiveSupport.on_load(:action_controller) do
          include Mixin
        end
      )
      expect(refs).to contain_exactly(%w[Include ActionController::Base Mixin], %w[Include ActionController::API Mixin])
    end

    it 'maps send(:include) and self.include' do
      refs = mixins_for %(
        ActiveSupport.on_load(:active_record) do
          send :include, First
          self.extend Second
        end
      )
      expect(refs).to eq([%w[Include ActiveRecord::Base First], %w[Extend ActiveRecord::Base Second]])
    end

    it 'maps hooks registered inside a class body and method' do
      refs = mixins_for %(
        module Engine
          class Railtie
            initializer 'x' do
              ActiveSupport.on_load(:active_record) { include Engine::Mixin }
            end

            def self.include_helpers
              ActiveSupport.on_load(:action_view) do
                include Engine::Helpers if defined?(Engine::Helpers)
              end
            end
          end
        end
      )
      expect(refs).to eq([%w[Include ActiveRecord::Base Engine::Mixin], %w[Include ActionView::Base Engine::Helpers]])
    end

    it 'ignores hooks it cannot map to a class' do
      refs = mixins_for %(
        ActiveSupport.on_load(:after_initialize) do
          include Mixin
        end
        Other.on_load(:active_record) do
          include Mixin
        end
      )
      expect(refs).to eq([['Include', '', 'Mixin'], ['Include', '', 'Mixin']])
    end

    it 'leaves mixins in nested namespaces alone' do
      refs = mixins_for %(
        ActiveSupport.on_load(:active_record) do
          class Nested
            include Mixin
          end
        end
      )
      expect(refs).to eq([%w[Include Nested Mixin]])
    end

    it 'exposes methods from a module included by a load hook' do
      api_map = Solargraph::ApiMap.new
      source = Solargraph::Source.load_string(%(
        module ActionController
          class Base; end
        end

        module Mixin
          def helper; end
        end

        ActiveSupport.on_load(:action_controller) do
          include Mixin
        end
      ), 'test.rb')
      api_map.map source
      expect(api_map.get_method_stack('ActionController::Base', 'helper').map(&:path)).to eq(['Mixin#helper'])
    end
  end
end
