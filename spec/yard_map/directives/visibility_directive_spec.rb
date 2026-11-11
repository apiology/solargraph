# frozen_string_literal: true

describe Solargraph::YardMap::Directives::VisibilityDirective do
  describe '.no_empty_lines?' do
    it 'is true when no line in the range is blank' do
      expect(described_class.no_empty_lines?("a\nb\n", 0, 1)).to be(true)
    end

    it 'is false when a line in the range is blank' do
      expect(described_class.no_empty_lines?("a\n\nb\n", 0, 2)).to be(false)
    end

    it 'is false when the range starts past the end of the code' do
      expect(described_class.no_empty_lines?("a\n", 5, 6)).to be(false)
    end
  end
end
