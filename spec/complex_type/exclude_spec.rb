# frozen_string_literal: true

describe Solargraph::ComplexType do
  let(:api_map) { Solargraph::ApiMap.new }

  let(:source) do
    Solargraph::Source.load_string(%(
      class Sup; end
      class Sub < Sup; end
      class Unrelated; end
    ))
  end

  before { api_map.map source }

  it 'excludes known subtypes of an excluded type, not just exact matches' do
    type = described_class.parse('Sub, Sup, Unrelated')
    result = type.exclude(described_class.parse('Sup'), api_map)
    expect(result.tags).to eq('Unrelated')
  end

  it 'falls back to bot when every member is excluded transitively' do
    type = described_class.parse('Sub, Sup')
    result = type.exclude(described_class.parse('Sup'), api_map)
    expect(result.tags).to eq('bot')
  end
end
