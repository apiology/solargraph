# frozen_string_literal: true

describe Solargraph::LanguageServer::Host::Diagnoser do
  it 'diagnoses on ticks' do
    host = double(Solargraph::LanguageServer::Host, options: { 'diagnostics' => true }, synchronizing?: false)
    diagnoser = described_class.new(host)
    diagnoser.schedule 'file.rb'
    allow(host).to receive(:diagnose)
    diagnoser.tick
    expect(host).to have_received(:diagnose).with('file.rb')
  end
end
