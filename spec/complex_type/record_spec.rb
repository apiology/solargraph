# frozen_string_literal: true

describe 'Solargraph::ComplexType::UniqueType::Record' do
  # Record is written against the Solargraph::Type contract and the
  # reduced type interface, and RBS records reach it only once those land.
  before do
    pending 'https://github.com/castwide/solargraph/pull/1459 ' \
            'https://github.com/castwide/solargraph/pull/1460 ' \
            'https://github.com/castwide/solargraph/pull/1104'
  end

  # Loaded inside each example, not when this file loads: its superclass
  # Solargraph::Type exists only once castwide/solargraph#1459 is in.
  let(:described_class) { Solargraph::ComplexType::UniqueType::Record }
  let(:api_map) { Solargraph::ApiMap.new }

  # The record `{ name: String, ?port: Integer }`, or another from +fields+
  def record fields = { name: '::String', port: '::Integer' }, optional_keys = [:port]
    types = fields.transform_values { |tag| Solargraph::ComplexType.parse(tag) }
    described_class.new(types, optional_keys)
  end

  it 'renders its tags as the Hash it describes' do
    expect(record.tags).to eq('Hash{Symbol => String, Integer}')
  end

  it 'renders its rooted tags as the Hash it describes' do
    expect(record.rooted_tags).to eq('::Hash{::Symbol => ::String, ::Integer}')
  end

  it 'prints itself back to RBS with optional fields marked' do
    expect(record.to_rbs).to eq('{ name: ::String, ?port: ::Integer }')
  end

  it 'prints string keys back to RBS as string keys' do
    expect(record({ 'id' => '::Integer' }, []).to_rbs).to eq("{ 'id' => ::Integer }")
  end

  it 'reads each field through its own literal-keyed [] overload' do
    signatures = record.method_stack_pins('[]', api_map).flat_map(&:signatures)
    expect(signatures.map { |sig| [sig.parameters.map { |param| param.return_type.tags }, sig.return_type.tags] })
      .to eq([[[':name'], 'String'], [[':port'], 'Integer, nil']])
  end

  it 'conforms where the Hash it describes is expected' do
    expected = Solargraph::ComplexType.parse('::Hash{::Symbol => ::String, ::Integer}')
    expect(record.conforms_to?(api_map, expected, :method_call)).to be(true)
  end

  it 'conforms to a record whose missing field is optional' do
    named = record({ name: '::String' }, [])
    expect(named.conforms_to?(api_map, Solargraph::ComplexType.new([record]), :method_call)).to be(true)
  end

  it 'does not conform to a record whose missing field is required' do
    named = record({ name: '::String' }, [])
    expected = Solargraph::ComplexType.new([record({ name: '::String', port: '::Integer' }, [])])
    expect(named.conforms_to?(api_map, expected, :method_call)).to be(false)
  end
end
