# frozen_string_literal: true

describe Solargraph::Convention do
  it 'newly defined pins are resolved by ApiMap after file changes' do
    filename = 'test.rb'

    # Initial code with one DSL call
    initial_code = <<~RUBY
      class MyModel
        dummy_dsl :existing_field
      end
    RUBY

    # Create a dummy convention that statically provides one method
    dummy_convention = Class.new(Solargraph::Convention::Base) do
      def local _source_map
        Solargraph::Environ.new(
          pins: [
            Solargraph::Pin::Method.new(
              name: 'existing_field',
              closure: Solargraph::Pin::Namespace.new(name: 'MyModel'),
              scope: :instance,
              location: Solargraph::Location.new('test.rb', Solargraph::Range.from_to(1, 2, 1, 27)),
              return_type: Solargraph::ComplexType.parse('String')
            )
          ]
        )
      end
    end

    described_class.register dummy_convention

    source = Solargraph::Source.load_string(initial_code, filename)
    api_map = Solargraph::ApiMap.new
    api_map.map(source)

    # Verify that the existing method works
    pins = api_map.get_path_pins('MyModel#existing_field')
    method_pin = pins.first
    expect(method_pin).not_to be_nil
    expect(method_pin.name).to eq('existing_field')

    # Now simulate adding a new DSL call by updating the source
    updated_code = <<~RUBY
      class MyModel
        dummy_dsl :existing_field
        dummy_dsl :newly_defined_field
      end
    RUBY

    # Unregister the old convention and register a new one with two methods
    described_class.unregister dummy_convention

    updated_dummy_convention = Class.new(Solargraph::Convention::Base) do
      def local _source_map
        Solargraph::Environ.new(
          pins: [
            Solargraph::Pin::Method.new(
              name: 'existing_field',
              closure: Solargraph::Pin::Namespace.new(name: 'MyModel'),
              scope: :instance,
              location: Solargraph::Location.new('test.rb', Solargraph::Range.from_to(1, 2, 1, 27)),
              return_type: Solargraph::ComplexType.parse('String')
            ),
            Solargraph::Pin::Method.new(
              name: 'newly_defined_field',
              closure: Solargraph::Pin::Namespace.new(name: 'MyModel'),
              scope: :instance,
              location: Solargraph::Location.new('test.rb', Solargraph::Range.from_to(2, 2, 2, 31)),
              return_type: Solargraph::ComplexType.parse('String')
            )
          ]
        )
      end
    end

    described_class.register updated_dummy_convention

    # Create an updater that represents the file being saved with new content
    updater = Solargraph::Source::Updater.new(
      filename,
      2, # version
      [
        # Replace the entire content
        Solargraph::Source::Change.new(
          Solargraph::Range.from_to(0, 0, source.code.lines.length - 1, source.code.lines.last.length),
          updated_code
        )
      ]
    )

    # Update the source
    updated_source = source.synchronize(updater)
    # Re-map the updated live source to refresh the API map - this tests the fix from 4d091c5c
    api_map.map(updated_source, live: true)

    # Now check that both methods are available
    pins = api_map.get_path_pins('MyModel#existing_field')
    method_pin = pins.first
    expect(method_pin).not_to be_nil
    expect(method_pin.name).to eq('existing_field')

    pins = api_map.get_path_pins('MyModel#newly_defined_field')
    method_pin = pins.first
    expect(method_pin).not_to be_nil
    expect(method_pin.name).to eq('newly_defined_field')

    described_class.unregister updated_dummy_convention
  end

  it 'registers a convention while another thread iterates the registry' do
    entered = Queue.new
    release = Queue.new

    # Blocks inside Convention.for_global until the main thread registers
    blocking_convention = Class.new(Solargraph::Convention::Base) do
      define_method(:global) do |_object|
        entered << true
        release.pop
        Solargraph::Environ.new
      end
    end
    other_convention = Class.new(Solargraph::Convention::Base)

    described_class.register blocking_convention
    reader = Thread.new { described_class.for_global(nil) }
    entered.pop

    expect { described_class.register other_convention }.not_to raise_error
  ensure
    release << true
    reader&.join
    described_class.unregister blocking_convention
    described_class.unregister other_convention
  end
end
