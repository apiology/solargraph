# frozen_string_literal: true

describe Solargraph::Collection::Gem do
  describe '.load_all' do
    let(:metagem) { instance_double(Solargraph::Metagem, name: 'example', version: '1.0.0') }

    it 'loads every gem it is given' do
      allow(described_class).to receive(:load)

      described_class.load_all([metagem, metagem])

      expect(described_class).to have_received(:load).with(metagem).twice
    end

    it 'rebuilds from scratch when asked' do
      allow(described_class).to receive(:load)
      allow(described_class).to receive(:uncache)

      described_class.load_all([metagem], rebuild: true)

      expect(described_class).to have_received(:uncache).with(metagem)
    end

    it 'reports how long a slow batch took' do
      allow(described_class).to receive(:load)
      stub_const("#{described_class}::SLOW_BATCH_MS", -1)
      out = StringIO.new

      described_class.load_all([metagem], out: out)

      expect(out.string).to match(/\ABuilt 1 gems in \d+ ms in \d+ threads\n\z/)
    end

    it 'stays quiet about a batch that was not slow' do
      allow(described_class).to receive(:load)
      out = StringIO.new

      described_class.load_all([metagem], out: out)

      expect(out.string).to be_empty
    end

    it 'does nothing without gems to load' do
      allow(described_class).to receive(:load)

      described_class.load_all([])

      expect(described_class).not_to have_received(:load)
    end
  end
end
