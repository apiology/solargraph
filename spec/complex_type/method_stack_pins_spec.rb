# frozen_string_literal: true

# #method_stack_pins answers with the pins implementing a method, or nil
# when nothing does. Its own nil answer is what a nested conjunct hands
# back, so the recursion has to accept it.
describe Solargraph::ComplexType::UniqueType::Intersection do
  let(:api_map) { Solargraph::ApiMap.new }

  def conjunct tag
    Solargraph::ComplexType.parse(tag)
  end

  it 'answers with the pins when a conjunct defines the method' do
    intersection = described_class.new([conjunct('::String'), conjunct('::Comparable')])
    expect(intersection.method_stack_pins('upcase', api_map).map(&:path)).to eq(['String#upcase'])
  end

  # The value satisfies every conjunct, so the narrowest return is the
  # one a call can rely on.
  it 'answers with the narrowest return when several conjuncts define the method' do
    intersection = described_class.new([conjunct('::StandardError'), conjunct('::_Raised')])
    expect(intersection.method_stack_pins('backtrace', api_map).map(&:path)).to eq(['_Raised#backtrace'])
  end

  it 'answers nil when no conjunct defines the method' do
    intersection = described_class.new([conjunct('::String'), conjunct('::Comparable')])
    expect(intersection.method_stack_pins('frobnicate', api_map)).to be_nil
  end

  # A conjunct is normally a ComplexType, which answers [] for an
  # unresolved method, but the class accepts a bare Intersection too - and
  # that answers nil, the same as this method does.
  it 'answers nil when a nested intersection conjunct resolves nothing' do
    nested = described_class.new([conjunct('::Integer')])
    intersection = described_class.new([conjunct('::String'), nested])
    expect(intersection.method_stack_pins('frobnicate', api_map)).to be_nil
  end
end
