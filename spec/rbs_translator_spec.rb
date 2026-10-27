# frozen_string_literal: true

require 'rbs'

describe Solargraph::RbsTranslator do
  # @param rbs_string [String]
  # @return [Solargraph::ComplexType]
  def translate rbs_string
    described_class.to_complex_type(RBS::Parser.parse_type(rbs_string))
  end

  context 'with literal type arguments' do
    it 'roots the class name but not a symbol literal argument' do
      expect(translate('::Array[:Sym]').rooted_tags).to eq('::Array<:Sym>')
    end

    it 'roots the class name but not a capitalized string literal key' do
      expect(translate('::Hash["Index", ::Float]').rooted_tags).to eq('::Hash{"Index" => ::Float}')
    end
  end
end
