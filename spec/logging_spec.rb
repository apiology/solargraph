# frozen_string_literal: true

require 'tempfile'

describe Solargraph::Logging do
  it 'logs messages with levels' do
    file = Tempfile.new('log')
    described_class.logger.reopen file
    described_class.logger.warn 'Test'
    file.rewind
    msg = file.read
    file.close
    file.unlink
    described_class.logger.reopen File::NULL
    expect(msg).to include('WARN')
  end

  it 'builds a logger at a class-specific log level' do
    klass = Class.new do
      include Solargraph::Logging

      def log_level
        :debug
      end

      def current_logger
        logger
      end
    end

    expect(klass.new.current_logger.level).to eq(Logger::DEBUG)
  end
end
