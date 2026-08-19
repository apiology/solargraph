# frozen_string_literal: true

# ComplexType#narrow_with is flow-sensitive type narrowing (e.g.
# refining a declared type using a type learned from an `is_a?`
# guard) - see spec/parser/flow_sensitive_typing_spec.rb for
# end-to-end coverage through real source. These specs exercise the
# narrowing logic directly.
describe Solargraph::ComplexType do
  let(:api_map) { Solargraph::ApiMap.new }

  context 'when narrowing a class with an unrelated mix-in' do
    let(:source) do
      Solargraph::Source.load_string(%(
        module M; end
        class T; end
      ))
    end

    before { api_map.map source }

    it 'builds an intersection rather than discarding both facts' do
      declared = described_class.parse('T')
      learned = described_class.parse('M')
      narrowed = declared.narrow_with(learned, api_map)
      expect(narrowed.first).to be_a(Solargraph::ComplexType::UniqueType::Intersection)
      expect(narrowed.tag).to eq('T & M')
    end

    it 'lets the narrowed intersection satisfy either original fact' do
      declared = described_class.parse('T')
      learned = described_class.parse('M')
      narrowed = declared.narrow_with(learned, api_map)
      expect(narrowed.conforms_to?(api_map, described_class.parse('T'), :method_call)).to be(true)
      expect(narrowed.conforms_to?(api_map, described_class.parse('M'), :method_call)).to be(true)
    end
  end

  context 'when the mix-in is already known to be included' do
    let(:source) do
      Solargraph::Source.load_string(%(
        module M; end
        class T
          include M
        end
      ))
    end

    before { api_map.map source }

    it 'simplifies to the already-more-specific type instead of building a redundant intersection' do
      declared = described_class.parse('T')
      learned = described_class.parse('M')
      narrowed = declared.narrow_with(learned, api_map)
      expect(narrowed.tag).to eq('T')
    end
  end

  # A truthiness split (`m || Mod`) narrows the left-hand side with
  # `nil, false` over the right-hand side's range. Neither falsy type
  # can describe the same value as a module object, so both pairs are
  # dropped and only the declared `nil` arm survives.
  context 'when narrowing a metatype with the falsy types from a truthiness split' do
    let(:source) do
      Solargraph::Source.load_string(%(
        module Mod; end
        class Klass; end
      ))
    end

    let(:falsy) { described_class.parse('nil', 'false').qualify(api_map) }

    before { api_map.map source }

    it 'drops a module metatype instead of pairing it as a mix-in' do
      declared = described_class.parse('Module<Mod>', 'nil').qualify(api_map)
      expect(declared.narrow_with(falsy, api_map).tag).to eq('nil')
    end

    it 'drops a class metatype the same way' do
      declared = described_class.parse('Class<Klass>', 'nil').qualify(api_map)
      expect(declared.narrow_with(falsy, api_map).tag).to eq('nil')
    end

    it 'leaves the result conforming to itself' do
      declared = described_class.parse('Module<Mod>', 'nil').qualify(api_map)
      narrowed = declared.narrow_with(falsy, api_map)
      expect(narrowed.conforms_to?(api_map, narrowed, :assignment)).to be(true)
    end

    it 'still pairs a genuine mix-in, which is the case the rule exists for' do
      declared = described_class.parse('Klass').qualify(api_map)
      learned = described_class.parse('Mod').qualify(api_map)
      expect(declared.narrow_with(learned, api_map).tag).to eq('Klass & Mod')
    end
  end

  # A class or module object can pick a module up with `extend`, so a
  # metatype is not disjoint from every module - only from ones it
  # could not be extended by.
  context 'when narrowing a metatype with a module it could extend' do
    let(:source) do
      Solargraph::Source.load_string(%(
        module Mod; end
        class Klass; extend Mod; end
      ))
    end

    before { api_map.map source }

    it 'pairs the class object with the module' do
      declared = described_class.parse('Class<Klass>').qualify(api_map)
      learned = described_class.parse('Mod').qualify(api_map)
      expect(declared.narrow_with(learned, api_map).tag).to eq('Class<Klass> & Mod')
    end

    it 'still drops the module object paired with a falsy type' do
      declared = described_class.parse('Module<Mod>').qualify(api_map)
      falsy = described_class.parse('nil', 'false').qualify(api_map)
      expect(declared.narrow_with(falsy, api_map).tag).to eq('undefined')
    end
  end

  # UniqueType#narrow_with defers to ComplexType rather than keeping a
  # second copy of the rules, which is what keeps the two from
  # disagreeing about which side to keep when both conform.
  context 'when the receiver is a single UniqueType' do
    let(:source) do
      Solargraph::Source.load_string(%(
        module M; end
        class T; end
      ))
    end

    before { api_map.map source }

    it 'produces the same result as the one-item union' do
      unique = described_class.parse('T').first
      learned = described_class.parse('M')
      expect(unique.narrow_with(learned, api_map).tag).to eq('T & M')
    end

    it 'returns itself untouched when there is nothing to narrow with' do
      unique = described_class.parse('T').first
      expect(unique.narrow_with(nil, api_map)).to be(unique)
    end
  end
end
