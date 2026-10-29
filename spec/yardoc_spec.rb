# frozen_string_literal: true

require 'tmpdir'
require 'open3'

describe Solargraph::Yardoc do
  around do |testobj|
    @tmpdir = Dir.mktmpdir

    testobj.run
  ensure
    FileUtils.remove_entry(@tmpdir)
  end

  let(:gem_yardoc_path) do
    File.join(@tmpdir, 'solargraph', 'yardoc', 'test_gem')
  end

  let(:gemspec) { Gem::Specification.find_by_name('backport') }
  let(:metagem) { Solargraph::Metagem.from_specification(gemspec) }

  before do
    FileUtils.mkdir_p(gem_yardoc_path)
  end

  describe '.path_for' do
    it 'gives a declared plugin set a path of its own' do
      expect(described_class.path_for(metagem, ['activesupport-concern']))
        .not_to eq(described_class.path_for(metagem, []))
    end

    it 'gives the same plugin set the same path whichever spelling names it' do
      expect(described_class.path_for(metagem, ['yard-activesupport-concern']))
        .to eq(described_class.path_for(metagem, ['activesupport-concern']))
    end
  end

  describe '.cache' do
    it 'saves yardoc caches from metagems' do
      described_class.cache(metagem, [])
      expect(File.exist?(described_class.path_for(metagem, []))).to be(true)
      expect(described_class.cached?(metagem, [])).to be(true)
    end
  end

  describe '.uncache' do
    it 'deletes yardoc caches' do
      described_class.uncache(metagem)
      expect(File.exist?(described_class.path_for(metagem, []))).to be(false)
      expect(described_class.cached?(metagem, [])).to be(false)
    end
  end

  describe '.processing?' do
    it 'returns true if the yardoc is being processed' do
      FileUtils.touch(File.join(gem_yardoc_path, 'processing'))
      expect(described_class.processing?(gem_yardoc_path)).to be(true)
    end

    it 'returns false if the yardoc is not being processed' do
      expect(described_class.processing?(gem_yardoc_path)).to be(false)
    end
  end

  describe '.load!' do
    it 'does not blow up when called on empty directory' do
      expect { described_class.load!(gem_yardoc_path) }.not_to raise_error
    end

    it 'loads metagem code objects from metagems' do
      described_class.cache(metagem, [])
      objects = described_class.load!(described_class.path_for(metagem, []))
      expect(objects.map(&:name)).to include(:Backport)
    end
  end

  describe '.build_docs' do
    let(:output) { '' }

    before do
      allow(Solargraph.logger).to receive(:warn)
      allow(Solargraph.logger).to receive(:info)
      FileUtils.rm_rf(gem_yardoc_path)
    end

    it 'builds docs for a gem' do
      described_class.build_docs(gem_yardoc_path, [], metagem)
      expect(File.exist?(File.join(gem_yardoc_path, 'complete'))).to be true
    end

    it 'bails quietly if directory given does not exist' do
      allow(Dir).to receive(:exist?).and_return(false)
      allow(Open3).to receive(:capture2e)

      expect do
        described_class.build_docs(gem_yardoc_path, [], metagem)
      end.not_to raise_error
      expect(Open3).not_to have_received(:capture2e)
    end

    it 'is idempotent' do
      described_class.build_docs(gem_yardoc_path, [], metagem)
      described_class.build_docs(gem_yardoc_path, [], metagem) # second time
      expect(File.exist?(File.join(gem_yardoc_path, 'complete'))).to be true
    end

    it 'passes each declared plugin to yard' do
      allow(Open3).to receive(:capture2e).and_return([output, instance_double(Process::Status, success?: true)])

      described_class.build_docs(gem_yardoc_path, ['activesupport-concern'], metagem)

      expect(Open3).to have_received(:capture2e)
        .with('yardoc', '--db', gem_yardoc_path, '--no-output',
              '--plugin', 'solargraph', '--plugin', 'activesupport-concern', chdir: metagem.full_path)
    end

    context 'with an error from yard' do
      before do
        allow(Open3).to receive(:capture2e).and_return([output, result])
      end

      let(:result) { instance_double(Process::Status) }

      it 'does not raise on error from yard' do
        allow(result).to receive(:success?).and_return(false)

        expect do
          described_class.build_docs(gem_yardoc_path, [], metagem)
        end.not_to raise_error
      end
    end
  end
end
