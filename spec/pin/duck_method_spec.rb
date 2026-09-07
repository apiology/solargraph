# frozen_string_literal: true

describe Solargraph::Pin::DuckMethod do
  let(:api_map) do
    Solargraph::ApiMap.new.tap do |map|
      map.map Solargraph::Source.load_string(%(
        class ClassTest
          def create_object(clazz)
            clazz.new
          end
        end
      ))
    end
  end

  # ClassTest carries its own inherited Class#new for an ancestor walk to find.
  let(:duck_new_at_call_site) do
    described_class.new(name: 'new', source: :api_map,
                        closure: api_map.get_path_pins('ClassTest#create_object').first)
  end

  it 'synthesizes a signature that accepts any arguments' do
    pin = described_class.new(name: 'new', source: :api_map)
    parameters = pin.signatures.first.parameters
    expect(parameters.map(&:decl)).to eq(%i[restarg kwrestarg])
  end

  it 'has no ancestor chain of its own to walk' do
    expect(duck_new_at_call_site.rest_of_stack(api_map)).to be_empty
  end

  it "infers nothing rather than the call site's own inherited #new" do
    expect(duck_new_at_call_site.typify(api_map)).to be_undefined
  end
end
