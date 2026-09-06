# frozen_string_literal: true

describe Solargraph::Pin::DuckMethod do
  it 'synthesizes a signature that accepts any arguments' do
    pin = described_class.new(name: 'new', source: :api_map)
    parameters = pin.signatures.first.parameters
    expect(parameters.map(&:decl)).to eq(%i[restarg kwrestarg])
  end
end
