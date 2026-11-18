# frozen_string_literal: true

require 'tmpdir'

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

    it 'stops its workers when a gem fails to load' do
      pools = []
      allow(Concurrent::FixedThreadPool).to receive(:new).and_wrap_original do |original, *args|
        original.call(*args).tap { |pool| pools << pool }
      end
      allow(described_class).to receive(:load).and_raise(RuntimeError, 'boom')

      expect { described_class.load_all([metagem]) }.to raise_error(RuntimeError, 'boom')

      expect(pools.map(&:running?)).to eq([false])
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

  describe '#pins' do
    around do |example|
      Dir.mktmpdir do |dir|
        @gem_dir = dir
        example.run
      end
    end

    # @param dependencies [Array<String>]
    # @return [Array<Solargraph::Pin::Base>]
    def gem_pins dependencies
      FileUtils.mkdir_p File.join(@gem_dir, 'lib', 'foo')
      File.write File.join(@gem_dir, 'lib', 'foo', 'logging.rb'), %(
        module Foo
          module Logging
            extend ActiveSupport::Concern

            included do
              cattr_accessor :logger, default: Logger.new($stdout)
              class_attribute :log_arguments, instance_accessor: false, default: true
            end
          end
        end
      )
      metagem = Solargraph::Metagem.new(name: 'foo', full_path: @gem_dir, spec_file: nil,
                                        source: "source at #{@gem_dir}", version: '1.0.0',
                                        require_paths: ['lib'], dependencies: dependencies)
      described_class.new(metagem).pins
    end

    it 'creates accessor pins for ActiveSupport macros in a gem depending on activesupport' do
      paths = gem_pins(['activesupport']).map(&:path)
      expect(paths).to include('Foo::Logging#logger', 'Foo::Logging#logger=',
                               'Foo::Logging.logger', 'Foo::Logging.logger=',
                               'Foo::Logging.log_arguments', 'Foo::Logging.log_arguments=')
    end

    it 'skips ActiveSupport macros in a gem without activesupport' do
      paths = gem_pins([]).map(&:path)
      expect(paths).not_to include('Foo::Logging#logger', 'Foo::Logging.log_arguments')
    end
  end
end
