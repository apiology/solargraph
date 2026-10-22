# frozen_string_literal: true

describe Solargraph::LanguageServer::Host::Diagnoser do
  it 'diagnoses on ticks' do
    host = instance_double(Solargraph::LanguageServer::Host, options: { 'diagnostics' => true }, synchronizing?: false)
    allow(host).to receive(:diagnose)
    diagnoser = described_class.new(host)
    diagnoser.schedule 'file.rb'
    diagnoser.tick
    expect(host).to have_received(:diagnose).with('file.rb')
  end

  it 'drops everything queued while diagnostics are off' do
    host = instance_double(Solargraph::LanguageServer::Host, options: { 'diagnostics' => false }, synchronizing?: false)
    allow(host).to receive(:diagnose)
    diagnoser = described_class.new(host)
    diagnoser.schedule 'file.rb'
    diagnoser.tick
    # Turning diagnostics back on gives the file a second chance to be
    # picked up, so a silent tick here is the queue being empty.
    allow(host).to receive(:options).and_return({ 'diagnostics' => true })
    diagnoser.tick
    expect(host).not_to have_received(:diagnose)
  end

  it 'retries a file whose source was out of sync with the api map' do
    host = instance_double(Solargraph::LanguageServer::Host, options: { 'diagnostics' => true }, synchronizing?: false)
    attempts = 0
    allow(host).to receive(:diagnose) do
      attempts += 1
      raise Solargraph::InvalidOffsetError if attempts == 1
    end
    diagnoser = described_class.new(host)
    diagnoser.schedule 'file.rb'
    diagnoser.tick
    diagnoser.tick
    expect(attempts).to eq(2)
  end

  it 'keeps going after a file fails to diagnose' do
    host = instance_double(Solargraph::LanguageServer::Host, options: { 'diagnostics' => true }, synchronizing?: false)
    allow(host).to receive(:diagnose).and_raise(RuntimeError, 'boom')
    allow(Solargraph::Logging.logger).to receive(:warn)
    diagnoser = described_class.new(host)
    diagnoser.schedule 'file.rb'
    expect { diagnoser.tick }.not_to raise_error
    # Unlike an invalid offset, a failure is not worth retrying, so the
    # second tick finds nothing left to do.
    diagnoser.tick
    expect(host).to have_received(:diagnose).once
    expect(Solargraph::Logging.logger).to have_received(:warn).with(/Error diagnosing file\.rb: \[RuntimeError\] boom/)
  end
end
