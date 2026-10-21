# frozen_string_literal: true

require 'rbs'

describe Solargraph::ComplexType::UniqueType::Intersection do
  let(:api_map) { Solargraph::ApiMap.new }

  # @param rbs [String]
  # @param variables [Array<Symbol>]
  # @return [Solargraph::ComplexType]
  def rbs_type rbs, variables: []
    Solargraph::RbsTranslator.to_complex_type(RBS::Parser.parse_type(rbs, variables: variables))
  end

  context 'when translated from RBS' do
    subject(:type) { rbs_type('String & Enumerable[String]') }

    it 'is a single intersection' do
      expect(type.items.map(&:class)).to eq([described_class])
    end

    it 'keeps each conjunct' do
      expect(type.first.conjuncts.map(&:tags)).to eq(['String', 'Enumerable<String>'])
    end

    it 'renders a tag' do
      expect(type.tags).to eq('String & Enumerable<String>')
    end

    it 'renders a rooted tag' do
      expect(type.rooted_tags).to eq('::String & ::Enumerable<::String>')
    end

    it 'renders RBS' do
      expect(type.to_rbs).to eq('::String & ::Enumerable[::String]')
    end

    it 'equals a second translation of the same RBS' do
      expect(type).to eq(rbs_type('String & Enumerable[String]'))
    end

    it 'hashes like a second translation of the same RBS' do
      expect(type.hash).to eq(rbs_type('String & Enumerable[String]').hash)
    end
  end

  context 'with a union conjunct' do
    subject(:type) { rbs_type('(Integer | String) & Comparable') }

    it 'keeps the union as one conjunct' do
      expect(type.first.conjuncts.map(&:length)).to eq([2, 1])
    end

    it 'brackets the union in its tag, since & binds tighter than a comma' do
      expect(type.tags).to eq('[Integer, String] & Comparable')
    end

    it 'parenthesizes the union in RBS' do
      expect(type.to_rbs).to eq('(::Integer | ::String) & ::Comparable')
    end
  end

  it 'nests inside a generic type argument' do
    type = rbs_type('Array[String & Comparable]')
    expect(type.first.subtypes.first).to be_a(described_class)
  end

  it 'stays one member of a union' do
    type = rbs_type('(String & Comparable) | nil')
    expect(type.items.map(&:class)).to eq([described_class, Solargraph::ComplexType::UniqueType])
  end

  it 'is not read from a YARD type tag' do
    expect(Solargraph::ComplexType.parse('String & Comparable').first).not_to be_a(described_class)
  end

  context 'when inferred' do
    let(:inferred) { rbs_type('String & Enumerable[String]') }

    it 'conforms to its first conjunct' do
      expect(inferred.conforms_to?(api_map, rbs_type('String'), :method_call)).to be(true)
    end

    it 'conforms to its second conjunct' do
      expect(inferred.conforms_to?(api_map, rbs_type('Enumerable[String]'), :method_call)).to be(true)
    end

    it 'does not conform to a type no conjunct satisfies' do
      expect(inferred.conforms_to?(api_map, rbs_type('Integer'), :method_call)).to be(false)
    end

    it 'conforms to an identical intersection whose conjuncts are unrelated' do
      expect(inferred.conforms_to?(api_map, rbs_type('String & Enumerable[String]'), :method_call)).to be(true)
    end

    it 'conforms regardless of conjunct order' do
      expect(inferred.conforms_to?(api_map, rbs_type('Enumerable[String] & String'), :method_call)).to be(true)
    end

    it 'conforms to a narrower intersection' do
      expect(inferred.conforms_to?(api_map, rbs_type('String & Object'), :method_call)).to be(true)
    end

    it 'does not conform to an intersection with a conjunct it lacks' do
      expect(inferred.conforms_to?(api_map, rbs_type('String & Integer'), :method_call)).to be(false)
    end

    it 'conforms to a union that contains it' do
      expect(inferred.conforms_to?(api_map, rbs_type('Integer | (String & Enumerable[String])'),
                                   :method_call)).to be(true)
    end

    it 'conforms to a duck type that one conjunct provides' do
      expect(inferred.conforms_to?(api_map, Solargraph::ComplexType.parse('#upcase'), :method_call)).to be(true)
    end

    it 'does not conform to a duck type that no conjunct provides' do
      expect(inferred.conforms_to?(api_map, Solargraph::ComplexType.parse('#not_a_method'), :method_call)).to be(false)
    end
  end

  context 'when expected' do
    let(:expected) { rbs_type('Object & Comparable') }

    it 'accepts a type that satisfies every conjunct' do
      expect(rbs_type('String').conforms_to?(api_map, expected, :method_call)).to be(true)
    end

    it 'rejects a type that satisfies only one conjunct' do
      expect(rbs_type('Array[String]').conforms_to?(api_map, expected, :method_call)).to be(false)
    end
  end

  it 'binds a generic inside a conjunct' do
    type = rbs_type('T & Comparable', variables: [:T]).resolve_generics_from_context(['T'], rbs_type('Integer'))
    expect(type.rooted_tags).to eq('::Integer & ::Comparable')
  end

  it 'qualifies each conjunct' do
    type = described_class.new([Solargraph::ComplexType.parse('String'), Solargraph::ComplexType.parse('Comparable')])
    expect(type.qualify(api_map).rooted_tags).to eq('::String & ::Comparable')
  end
end
