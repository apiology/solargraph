# frozen_string_literal: true

describe Solargraph::PinCache do
  let(:workspace) { Solargraph::Workspace.new(Dir.pwd) }

  let(:configured) do
    described_class.new(rbs_collection_path: workspace.rbs_collection_path,
                        rbs_collection_config_path: workspace.rbs_collection_config_path)
  end

  let(:unconfigured) do
    described_class.new(rbs_collection_path: nil, rbs_collection_config_path: nil)
  end

  after do
    described_class.all_combined_pins_in_memory.clear
  end

  describe '#cache_key_for' do
    it 'differs between configurations that resolve the gem differently' do
      gemspec = Gem::Specification.find_by_name('addressable')

      expect(configured.cache_key_for(gemspec)).not_to eq(unconfigured.cache_key_for(gemspec))
    end
  end

  describe '#deserialize_combined_gem' do
    it 'does not serve one configuration the pins held for another' do
      gemspec = Gem::Specification.find_by_name('addressable')
      pins = [Solargraph::Pin::Namespace.new(name: 'Fixture')]
      described_class.all_combined_pins_in_memory[
        [gemspec.name, gemspec.version, configured.cache_key_for(gemspec)]
      ] = pins

      allow(described_class).to receive(:deserialize_combined_gem).and_return(nil)

      expect(unconfigured.deserialize_combined_gem(gemspec)).to be_nil
    end
  end

  describe '#uncache_gem' do
    it 'drops the in-memory entry as well as the files' do
      gemspec = Gem::Specification.find_by_name('backport')
      key = [gemspec.name, gemspec.version, configured.cache_key_for(gemspec)]
      described_class.all_combined_pins_in_memory[key] = []
      allow(described_class).to receive(:uncache_gem)

      configured.uncache_gem(gemspec, out: nil)

      expect(described_class.all_combined_pins_in_memory).not_to have_key(key)
    end
  end
end
