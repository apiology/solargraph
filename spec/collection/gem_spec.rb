# frozen_string_literal: true

describe Solargraph::Collection::Gem do
  let(:full_path) { File.expand_path('../fixtures/gem-with-app-dir', __dir__) }

  let(:metagem) do
    Solargraph::Metagem.new(
      name: 'gem-with-app-dir',
      full_path: full_path,
      spec_file: File.join(full_path, 'gem-with-app-dir.gemspec'),
      source: "source at `#{full_path}`",
      version: '0.1.0',
      require_paths: ['lib'],
      dependencies: []
    )
  end

  let(:paths) { described_class.new(metagem).pins.map(&:path) }

  it 'maps methods in require paths' do
    expect(paths).to include('GemWithAppDir.lib_method')
  end

  it 'maps methods in the app directory' do
    expect(paths).to include('GemWithAppDir::Broadcastable#broadcast_example')
  end
end
