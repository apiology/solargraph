# frozen_string_literal: true

describe Solargraph::GemPins, '.combine' do
  context 'with a namespace pin split across YARD and RBS' do
    # A real YARD-derived namespace pin always carries a location (the
    # .rb file it was parsed from), while a real RBS-derived one only
    # ever sets type_location - so the two are never Pin::Base#==
    # equal, and combine_pins always actually merges them rather than
    # taking its identical-pin shortcut. Set location here so this
    # fixture matches that.
    let(:yard_pin) do
      Solargraph::Pin::Namespace.new(
        name: 'Foo::Bar',
        type: :class,
        location: Solargraph::Location.new('foo/bar.rb', Solargraph::Range.from_to(0, 0, 0, 0)),
        closure: Solargraph::Pin::ROOT_PIN,
        source: :yardoc
      )
    end

    let(:rbs_pin) do
      Solargraph::Pin::Namespace.new(
        name: 'Foo::Bar',
        type: :class,
        generics: %w[T U],
        closure: Solargraph::Pin::ROOT_PIN,
        source: :rbs
      )
    end

    let(:combined) { described_class.combine([yard_pin], [rbs_pin]) }

    it 'merges the two pins into one, rather than dropping the RBS pin' do
      expect(combined.length).to eq(1)
    end

    it 'keeps the RBS-derived generics on the merged pin' do
      expect(combined.first.generics).to eq(%w[T U])
    end

    it 'marks the merged pin as combined' do
      expect(combined.first.source).to eq(:combined)
    end
  end
end
