# frozen_string_literal: true

describe Solargraph::PinCache do
  describe '.possible_stdlibs' do
    it 'lists names from the stdlib directory without the .rb suffix' do
      allow(Dir).to receive(:glob).and_return(['/ruby/3.2.0/set.rb', '/ruby/3.2.0/json'])

      expect(described_class.possible_stdlibs).to eq(%w[json set])
    end

    it 'is tolerant of less usual Ruby installations' do
      stub_const('Gem::RUBYGEMS_DIR', nil)

      expect(described_class.possible_stdlibs).to eq([])
    end
  end
end
