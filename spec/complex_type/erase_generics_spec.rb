# frozen_string_literal: true

describe Solargraph::ComplexType do
  describe '#erase_generics' do
    it 'keeps every member of a union' do
      expect(described_class.parse('Integer', 'String', 'nil').erase_generics(['T']).tags)
        .to eq('Integer, String, nil')
    end

    it 'erases a generic that is not the first member' do
      expect(described_class.parse('String', 'generic<T>').erase_generics(['T'])).to be_undefined
    end
  end
end
