# frozen_string_literal: true

describe Solargraph do
  describe '.with_clean_env' do
    it 'falls back to Bundler.with_clean_env' do
      allow(Bundler).to receive(:respond_to?).and_call_original
      allow(Bundler).to receive(:respond_to?).with(:with_original_env).and_return(false)
      allow(Bundler).to receive(:with_clean_env).and_yield
      ran = false

      described_class.with_clean_env { ran = true }

      expect(ran).to be(true)
    end
  end
end
