# frozen_string_literal: true

describe Solargraph::Collection::Gem do
  # @param name [String]
  # @return [Solargraph::Metagem]
  def fixture_gem name
    full_path = File.absolute_path(File.join('spec', 'fixtures', name))
    Solargraph::Metagem.new(name: name, full_path: full_path,
                            spec_file: File.join(full_path, "#{name}.gemspec"),
                            source: "source at #{full_path}", version: '1.0.0',
                            require_paths: ['lib'], dependencies: [])
  end

  # @return [Array<String>]
  def mapped_paths
    described_class.new(fixture_gem('engine_gem')).pins.map(&:path)
  end

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

  context 'with a convention that names extra source paths' do
    let(:app_convention) do
      Class.new(Solargraph::Convention::Base) do
        def extra_source_paths(root:, require_paths:, **)
          return [] unless root.end_with?('engine_gem') && require_paths == ['lib']

          ['app/models', 'app/models/concerns']
        end
      end
    end

    before { Solargraph::Convention.register app_convention }

    after { Solargraph::Convention.unregister app_convention }

    it 'maps the extra source paths' do
      expect(mapped_paths).to include('EngineGem::Broadcastable#broadcast')
    end

    it 'maps a file under overlapping paths once' do
      expect(mapped_paths.count('EngineGem::Broadcastable#broadcast')).to eq(1)
    end
  end

  it 'maps only require paths without such a convention' do
    expect(mapped_paths).not_to include('EngineGem::Broadcastable#broadcast')
  end
end
