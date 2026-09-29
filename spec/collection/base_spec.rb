# frozen_string_literal: true

require 'tmpdir'

describe Solargraph::Collection::Base do
  let(:pin) { Solargraph::Pin::Namespace.new(name: 'Example', type: :class) }

  let(:klass) do
    Class.new(described_class) do
      attr_accessor :pins

      def cache_file
        File.join Solargraph::CacheDir.base_dir, 'example.ser'
      end
    end
  end

  let(:base) { klass.new }

  it 'saves caches' do
    base.pins = [pin]
    base.load
    expect(File).to be_file(base.cache_file)
  end

  it 'loads from caches' do
    base.pins = []
    cache = base.load
    expect(cache).to eq([pin])
  end

  it 'deletes caches' do
    klass.uncache
    expect(File).not_to be_file(base.cache_file)
  end

  describe 'writing the cache file' do
    # Writing straight to the final path lets any other reader or writer
    # of it - a parallel_tests worker process, or another thread inside
    # Collection::Gem.load_all - observe a half-written file while the
    # dump is in flight. Renaming over it is atomic on one filesystem.
    let(:dir) { Dir.mktmpdir }
    let(:cache_file) { File.join(dir, 'atomic.ser') }
    let(:atomic_klass) do
      file = cache_file
      Class.new(described_class) do
        attr_accessor :pins

        define_method(:cache_file) { file }
      end
    end
    let(:collection) { atomic_klass.new }

    after { FileUtils.remove_entry dir }

    it 'writes to a temp file and renames it over the target' do
      collection.pins = [pin]
      written = nil
      renamed = nil
      allow(File).to receive(:write).and_wrap_original do |original, path, *args, **kwargs|
        written = path
        original.call(path, *args, **kwargs)
      end
      allow(File).to receive(:rename).and_wrap_original do |original, from, to|
        renamed = [from, to]
        original.call(from, to)
      end

      collection.load

      expect(written).not_to eq(cache_file)
      expect(renamed).to eq([written, cache_file])
    end

    it 'leaves no temp file behind' do
      collection.pins = [pin]
      collection.load
      expect(Dir.glob("#{cache_file}*")).to eq([cache_file])
    end

    it 'round-trips pins through the file' do
      collection.pins = [pin]
      collection.load
      # Drop the in-memory copy so the second load has to read the file.
      Solargraph::Collection.mem_cache.delete cache_file

      expect(atomic_klass.new.load.map(&:name)).to eq([pin.name])
    end
  end
end
