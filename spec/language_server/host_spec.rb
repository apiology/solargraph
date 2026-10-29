# frozen_string_literal: true

require 'tmpdir'
require 'timeout'

describe Solargraph::LanguageServer::Host do
  it 'prepares a workspace' do
    host = described_class.new
    Dir.mktmpdir do |dir|
      host.prepare(dir)
      expect(host.libraries.first).not_to be_nil
    end
  end

  it 'processes responses to message requests' do
    host = described_class.new
    done_somethings = 0
    host.send_request 'window/showMessageRequest', {
      'message' => 'Message',
      'actions' => ['Do something']
    } do |response|
      done_somethings += 1 if response == 'Do something'
    end
    expect(host.pending_requests.length).to eq(1)
    host.receive({
                   'id' => host.pending_requests.first,
                   'result' => 'Do something'
                 })
    expect(done_somethings).to eq(1)
  end

  it 'creates files from disk' do
    Dir.mktmpdir do |dir|
      host = described_class.new
      host.prepare dir
      file = File.join(dir, 'test.rb')
      File.write(file, "foo = 'foo'")
      uri = Solargraph::LanguageServer::UriHelpers.file_to_uri(file)
      result = host.create(uri)
      expect(result).to be(true)
    end
  end

  it 'deletes files' do
    Dir.mktmpdir do |dir|
      expect do
        host = described_class.new
        file = File.join(dir, 'test.rb')
        File.write(file, "foo = 'foo'")
        host.prepare dir
        uri = Solargraph::LanguageServer::UriHelpers.file_to_uri(file)
        host.delete(uri)
      end.not_to raise_error
    end
  end

  it 'cancels requests' do
    host = described_class.new
    host.cancel 1
    expect(host.cancel?(1)).to be(true)
  end

  it 'runs diagnostics on opened files' do
    Dir.mktmpdir do |dir|
      host = described_class.new
      # The host notifies its observers each time it queues a message
      queued = Thread::Queue.new
      host.add_observer(-> { queued.push(true) }, :call)
      host.configure({ 'diagnostics' => true })
      file = File.join(dir, 'test.rb')
      File.write(file, "foo = 'foo'")
      host.start
      host.prepare dir
      file_uri = Solargraph::LanguageServer::UriHelpers.file_to_uri(file)
      host.open(file, File.read(file), 1)
      # keep this from syncing a bunch of bundle gems in background
      library = host.library_for(file_uri)
      allow(library).to receive(:cacheable_specs).and_return([])
      buffer = host.flush
      # Wake on each queued message until the diagnoser's arrives
      Timeout.timeout 60 do
        until buffer.include?('textDocument/publishDiagnostics')
          queued.pop
          buffer += host.flush
        end
      end
      expect(buffer).to include('textDocument/publishDiagnostics')
    ensure
      host.fully_stop
    end
  end

  it 'gives up on a host whose threads never wind down', time_limit_seconds: 10 do
    host = described_class.new
    allow(host).to receive(:fully_stopped?).and_return(false)
    expect { host.fully_stop(timeout: 0) }.to raise_error(/did not fully stop within 0 seconds/)
  end

  it 'names a library still caching gems when it gives up', time_limit_seconds: 10 do
    Dir.mktmpdir do |dir|
      host = described_class.new
      host.prepare dir
      library = host.libraries.first
      allow(library).to receive(:fully_stopped?).and_return(false)
      expect { host.fully_stop(timeout: 0) }.to raise_error(/: library #{Regexp.escape(dir.inspect)} still running/)
    end
  end

  it 'handles DiagnosticsErrors' do
    host = described_class.new
    library = instance_double(Solargraph::Library)
    allow(library).to receive(:diagnose).and_raise(Solargraph::DiagnosticsError)
    allow(library).to receive_messages(contain?: true, synchronized?: true, mapped?: true)
    allow(library).to receive(:attach)
    allow(library).to receive(:merge)
    allow(library).to receive(:catalog)
    # @todo Smelly instance variable access
    host.instance_variable_set(:@libraries, [library])
    host.open('file:///test.rb', '', 0)
    expect do
      host.diagnose 'file:///test.rb'
    end.not_to raise_error
    result = host.flush
    expect(result).to include('Error in diagnostics')
  end

  it 'opens multiple folders' do
    host = described_class.new
    app1_folder = File.absolute_path('spec/fixtures/workspace_folders/folder1').gsub('\\', '/')
    app2_folder = File.absolute_path('spec/fixtures/workspace_folders/folder2').gsub('\\', '/')
    host.prepare(app1_folder)
    host.prepare(app2_folder)
    file1_uri = Solargraph::LanguageServer::UriHelpers.file_to_uri("#{app1_folder}/app.rb")
    file2_uri = Solargraph::LanguageServer::UriHelpers.file_to_uri("#{app2_folder}/app.rb")
    host.open_from_disk file1_uri
    library = host.library_for(file1_uri)
    # keep this from syncing a bunch of bundle gems in background
    allow(library).to receive(:cacheable_specs).and_return([])
    host.open_from_disk file2_uri
    library = host.library_for(file2_uri)
    # keep this from syncing a bunch of bundle gems in background
    allow(library).to receive(:cacheable_specs).and_return([])
    app1_map = host.document_symbols(file1_uri).map(&:path)
    expect(app1_map).to include('Folder1App')
    expect(app1_map).not_to include('Folder2App')
    app2_map = host.document_symbols(file2_uri).map(&:path)
    expect(app2_map).to include('Folder2App')
    expect(app2_map).not_to include('Folder1App')
  ensure
    host.stop
  end

  it "sends a library's progress to the client" do
    host = described_class.new
    host.client_capabilities = { 'window' => { 'workDoneProgress' => true } }
    progress = Solargraph::LanguageServer::Progress.new('Testing')
    progress.begin('Started', 0)
    Dir.mktmpdir do |dir|
      host.prepare(dir)
      library = host.libraries.first
      library.changed
      library.notify_observers progress
    end
    expect(host.flush).to include(%("method":"$/progress","params":{"token":"#{progress.uuid}"))
  ensure
    host.stop
  end

  it 'stops' do
    host = described_class.new
    host.fully_stop
    expect(host.fully_stopped?).to be(true)
  end

  it 'stops caching gems in the background when stopped' do
    Dir.mktmpdir do |dir|
      host = described_class.new
      host.prepare dir
      library = host.libraries.first
      # A gem that never becomes cached keeps the chain going forever
      gem = instance_double(Solargraph::Metagem, name: 'uncacheable', version: '1.0')
      allow(library.send(:api_map)).to receive(:unloaded_gems).and_return(Set[gem])
      allow(Solargraph::Yardoc).to receive(:processing?).and_return(false)
      caches = 0
      status = instance_double(Process::Status, success?: true)
      # Count only this library's cache runs: earlier examples leave
      # libraries caching their own gems in the background
      allow(Open3).to receive(:capture3).and_call_original
      allow(Open3).to receive(:capture3).with(anything, 'cache', 'uncacheable', any_args) do
        caches += 1
        sleep 0.1
        ['', '', status]
      end

      library.catalog
      library.diagnose File.join(dir, 'foo.rb')
      Timeout.timeout(10) { sleep 0.01 until caches.positive? }
      Timeout.timeout(10) { host.fully_stop }
      started = caches
      sleep 0.5

      expect(caches).to eq(started)
    end
  end

  it 'stops a library made while it is stopping' do
    host = described_class.new
    host.configure({ 'diagnostics' => true })
    # Hold the diagnoser inside Library.new so the generic library it makes
    # appears only after fully_stop has stopped the existing libraries
    building = Thread::Queue.new
    release = Thread::Queue.new
    allow(Solargraph::Library).to receive(:new).and_wrap_original do |original, *args|
      building.push(true)
      release.pop
      original.call(*args)
    end
    host.start
    host.open('file:///test.rb', 'class Foo; end', 1)
    Timeout.timeout(10) { building.pop }
    Thread.new do
      sleep 0.3
      release.push(true)
    end

    expect { host.fully_stop(timeout: 3) }.not_to raise_error
  end

  it 'retains orphaned sources' do
    dir = File.absolute_path('spec/fixtures/workspace')
    file = File.join(dir, 'lib', 'thing.rb')
    file_uri = Solargraph::LanguageServer::UriHelpers.uri_to_file(file)
    host = described_class.new
    host.prepare(dir)
    host.open(file_uri, File.read(file), 1)
    host.remove(dir)
    # keep this from syncing a bunch of bundle gems in background
    library = host.library_for(file_uri)
    allow(library).to receive(:cacheable_specs).and_return([])
    expect do
      host.document_symbols(file_uri)
    end.not_to raise_error
  ensure
    host.stop
  end

  it 'responds with empty diagnostics for unopened files' do
    host = described_class.new
    host.diagnose 'file:///file.rb'
    response = host.flush
    json = JSON.parse(response.lines.last)
    expect(json['method']).to eq('textDocument/publishDiagnostics')
    expect(json['params']['diagnostics']).to be_empty
  ensure
    host.stop
  end

  it 'rescues runtime errors from messages' do
    host = described_class.new
    message_class = Class.new(Solargraph::LanguageServer::Message::Base) do
      def process
        raise 'Always raise an error from this message'
      end
    end
    Solargraph::LanguageServer::Message.register('raiseRuntimeError', message_class)
    expect do
      host.receive({
                     'id' => 1,
                     'method' => 'raiseRuntimeError',
                     'params' => {}
                   })
    end.not_to raise_error
  end

  it 'ignores invalid messages' do
    host = described_class.new
    expect do
      host.receive({ 'bad' => 'message' })
    end.not_to raise_error
  end

  it 'repairs simple breaking changes without incremental sync' do
    file = '/test.rb'
    uri = Solargraph::LanguageServer::UriHelpers.file_to_uri(file)
    host = described_class.new
    host.prepare ''
    host.open uri, 'Foo::Bar', 1
    Timeout.timeout 60 do
      sleep 0.1 until host.libraries.all?(&:mapped?)
    end
    host.change({
                  'textDocument' => {
                    'uri' => uri,
                    'version' => 2
                  },
                  'contentChanges' => [
                    {
                      'text' => 'Foo::Bar.'
                    }
                  ]
                })
    source = host.sources.find(uri)
    # @todo Smelly private method access
    expect(source.send(:repaired)).to eq('Foo::Bar ')
  ensure
    host.stop
  end

  describe '#locate_pins' do
    it 'locates #initialize for Class#new calls' do
      code = %(
        class Example
          # the initialize method
          def initialize(foo); end
        end
        Foo.new
      )

      file = '/test.rb'
      uri = Solargraph::LanguageServer::UriHelpers.file_to_uri(file)
      host = described_class.new
      host.prepare ''
      host.open uri, code, 1
      library = host.library_for(uri)
      # keep this from syncing a bunch of bundle gems in background
      allow(library).to receive(:cacheable_specs).and_return([])
      Timeout.timeout 60 do
        sleep 0.1 until host.libraries.all?(&:mapped?)
      end
      result = host.locate_pins({
                                  'data' => {
                                    'uri' => uri,
                                    'location' => {
                                      'range' => {
                                        'start' => {
                                          'line' => 5,
                                          'character' => 12
                                        },
                                        'end' => {
                                          'line' => 5,
                                          'character' => 15
                                        }
                                      }
                                    },
                                    'path' => 'Example.new'
                                  }
                                })
      expect(result.map(&:path)).to include('Example.new')
    ensure
      host.stop
    end
  end

  describe '#references_from' do
    it 'rescues FileNotFound errors' do
      host = described_class.new
      expect { host.references_from('file:///not_a_file.rb', 1, 1) }.not_to raise_error
    end

    it 'logs FileNotFound errors' do
      allow(Solargraph.logger).to receive(:warn)
      host = described_class.new
      host.references_from('file:///not_a_file.rb', 1, 1)
      expect(Solargraph.logger).to have_received(:warn).with(/FileNotFoundError/)
    end

    it 'rescues InvalidOffset errors' do
      host = described_class.new
      uri = 'file:///file.rb'
      host.open(uri, 'class Foo; end', 1)
      library = host.library_for(uri)
      # keep this from syncing a bunch of bundle gems in background
      allow(library).to receive(:cacheable_specs).and_return([])
      expect { host.references_from('file:///file.rb', 0, 100) }.not_to raise_error
    ensure
      host.stop
    end

    it 'logs InvalidOffset errors' do
      allow(Solargraph.logger).to receive(:warn)
      host = described_class.new
      uri = 'file:///file.rb'
      host.open(uri, 'class Foo; end', 1)
      library = host.library_for(uri)
      # keep this from syncing a bunch of bundle gems in background
      allow(library).to receive(:cacheable_specs).and_return([])
      host.references_from(uri, 0, 100)
      expect(Solargraph.logger).to have_received(:warn).with(/InvalidOffsetError/)
    ensure
      host.stop
    end
  end

  describe 'Workspace variations' do
    before do
      @host = described_class.new
    end

    after do
      @host.fully_stop
    end

    it 'creates a library for a file without a workspace' do
      uri = 'file:///file.rb'
      @host.open(uri, 'class Foo; end', 1)
      library = @host.library_for(uri)
      # keep this from syncing a bunch of bundle gems in background
      allow(library).to receive(:cacheable_specs).and_return([])
      symbols = @host.document_symbols(uri)
      expect(symbols).not_to be_empty
    end

    it 'opens a file outside of prepared libraries' do
      @host.prepare(File.absolute_path(File.join('spec', 'fixtures', 'workspace')))
      uri = 'file:///file.rb'
      @host.open(uri, 'class Foo; end', 1)
      library = @host.library_for(uri)
      # keep this from syncing a bunch of bundle gems in background
      allow(library).to receive(:cacheable_specs).and_return([])
      symbols = @host.document_symbols(uri)
      expect(symbols).not_to be_empty
    end
  end
end
