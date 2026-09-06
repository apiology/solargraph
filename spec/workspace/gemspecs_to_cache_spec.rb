# frozen_string_literal: true

describe Solargraph::Workspace, '#gemspecs_to_cache' do
  subject(:selected) { workspace.gemspecs_to_cache }

  let(:workspace) { described_class.new('spec/fixtures/workspace') }
  let(:gemspecs) { instance_double(Solargraph::Workspace::Gemspecs) }
  let(:bundled) { instance_double(Gem::Specification, name: 'rspec', version: '3.13.0') }
  let(:stdlib) { instance_double(Gem::Specification, name: 'json', version: '2.7.0') }

  before do
    allow(Solargraph::Workspace::Gemspecs).to receive(:new).and_return(gemspecs)
    allow(gemspecs).to receive(:all_gemspecs_from_bundle).and_return([bundled])
    allow(Solargraph::PinCache).to receive(:possible_stdlibs).and_return(%w[json notagem])
    allow(gemspecs).to receive(:find_gem).with('json', out: nil).and_return(stdlib)
    allow(gemspecs).to receive(:find_gem).with('notagem', out: nil).and_return(nil)
  end

  it 'combines the bundle with the standard libraries that resolve to a gemspec' do
    expect(selected).to eq([bundled, stdlib])
  end

  it 'does not fall back to every gem installed on the machine' do
    allow(Gem::Specification).to receive(:to_a)

    selected

    expect(Gem::Specification).not_to have_received(:to_a)
  end

  it 'keeps one entry when the bundle and a standard library name resolve to the same gem' do
    allow(gemspecs).to receive(:all_gemspecs_from_bundle).and_return([bundled, stdlib])

    expect(selected).to eq([bundled, stdlib])
  end
end
