# frozen_string_literal: true

describe Solargraph::CacheDir do
  subject(:cache_dir) { described_class.new }

  # @param version [String]
  # @return [Hash{String => Gem::Specification}]
  def loaded_plugin_gem version
    spec = Gem::Specification.new do |s|
      s.name = 'fake-plugin'
      s.version = version
    end
    { 'fake-plugin' => spec }
  end

  it 'keeps the gem directory when no plugin is added' do
    expect(cache_dir.gem_dir).to eq(File.join(described_class.work_dir, 'gems'))
  end

  it 'separates gem caches built with a plugin' do
    cache_dir.add_plugin 'some_plugin'
    expect(cache_dir.gem_dir).not_to eq(described_class.new.gem_dir)
  end

  it 'separates gem caches built with different plugin versions' do
    allow(Gem).to receive(:loaded_specs).and_return(loaded_plugin_gem('1.0.0'))
    cache_dir.add_plugin 'fake-plugin'

    other = described_class.new
    allow(Gem).to receive(:loaded_specs).and_return(loaded_plugin_gem('1.1.0'))
    other.add_plugin 'fake-plugin'
    expect(other.gem_dir).not_to eq(cache_dir.gem_dir)
  end

  it 'does not depend on the order plugins are added in' do
    cache_dir.add_plugin 'first_plugin'
    cache_dir.add_plugin 'second_plugin'

    reversed = described_class.new
    reversed.add_plugin 'second_plugin'
    reversed.add_plugin 'first_plugin'
    expect(reversed.gem_dir).to eq(cache_dir.gem_dir)
  end

  it 'keeps each instance separate' do
    cache_dir.add_plugin 'some_plugin'
    expect(described_class.new.plugins).to be_empty
  end
end
