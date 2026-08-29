# frozen_string_literal: true

require 'rbs'

describe Solargraph::RbsTranslator do
  describe '.to_complex_type' do
    it 'does not mislabel an RBS::Types::Intersection as a Union' do
      string_type = RBS::Types::ClassInstance.new(name: RBS::TypeName.parse('::String'), args: [], location: nil)
      integer_type = RBS::Types::ClassInstance.new(name: RBS::TypeName.parse('::Integer'), args: [], location: nil)
      intersection = RBS::Types::Intersection.new(types: [string_type, integer_type], location: nil)

      complex_type = described_class.to_complex_type(intersection)

      # Master's type_to_tag joins Intersection members with ', ' -
      # identical to how it joins Union members - so the result parses
      # back as `(String | Integer)`, a *union*, rather than reporting
      # that intersections aren't representable.
      expect(complex_type.to_rbs).not_to eq('(::String | ::Integer)')
      expect(complex_type.undefined?).to be true
    end
  end
end
