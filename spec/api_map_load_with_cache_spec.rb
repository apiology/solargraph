# frozen_string_literal: true

describe Solargraph::ApiMap do
  describe '.load_with_cache' do
    let(:metagem) { instance_double(Solargraph::Metagem, name: 'thor', cache_name: 'thor-1.3.0') }

    # Building a gem under one set of plugins and then reading it back under
    # another finds nothing, because the plugin set is part of the cache key.
    # A warm cache hides that; a cold one returns no pins at all.
    it 'builds an uncached gem under the plugins the workspace declares' do
      external = instance_double(Solargraph::External, unloaded_gems: [metagem])
      api_map = instance_double(described_class,
                                external: external,
                                yard_plugins: ['activesupport-concern'])
      allow(described_class).to receive(:load).and_return(api_map)
      allow(Solargraph::Collection::Gem).to receive(:load)

      described_class.load_with_cache('.', nil)

      expect(Solargraph::Collection::Gem).to have_received(:load)
        .with(metagem, ['activesupport-concern'])
    end
  end
end
