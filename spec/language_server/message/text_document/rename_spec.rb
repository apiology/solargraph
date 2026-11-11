# frozen_string_literal: true

describe Solargraph::LanguageServer::Message::TextDocument::Rename do
  let(:temp_file_url) do
    # "file://#{Dir.mktmpdir}/file.rb"
    'file:///file.rb'
  end

  # Rename#process catalogs the library before it searches, so one call
  # gives the final answer; show the whole result when the file is missing.
  def process_changes rename, url
    rename.process
    changes = rename.result[:changes][url]
    raise "No rename changes for #{url}: #{rename.result.inspect}" unless changes

    changes
  end

  it 'renames a symbol' do
    host = Solargraph::LanguageServer::Host.new
    host.start
    host.open(temp_file_url, %(
      class Foo
      end
      foo = Foo.new
    ), 1)
    rename = described_class.new(host, {
                                   'id' => 1,
                                   'method' => 'textDocument/rename',
                                   'params' => {
                                     'textDocument' => {
                                       'uri' => temp_file_url
                                     },
                                     'position' => {
                                       'line' => 1,
                                       'character' => 12
                                     },
                                     'newName' => 'Bar'
                                   }
                                 })
    # keep this from syncing a bunch of bundle gems in background
    library = host.library_for(temp_file_url)
    library.stop
    changes = process_changes(rename, temp_file_url)
    expect(changes.length).to eq(2)
  ensure
    host.fully_stop
  end

  it 'renames an argument symbol from method signature' do
    host = Solargraph::LanguageServer::Host.new
    host.start
    host.open(temp_file_url, %(
      class Example
      def foo(bar)
      bar += 1
      return bar
      end
    	end

    ), 1)
    rename = described_class.new(host, {
                                   'id' => 1,
                                   'method' => 'textDocument/rename',
                                   'params' => {
                                     'textDocument' => {
                                       'uri' => temp_file_url
                                     },
                                     'position' => {
                                       'line' => 3,
                                       'character' => 6
                                     },
                                     'newName' => 'baz'
                                   }
                                 })
    # keep this from syncing a bunch of bundle gems in background
    library = host.library_for(temp_file_url)
    library.stop
    changes = process_changes(rename, temp_file_url)
    expect(changes.length).to eq(3)
  ensure
    host.fully_stop
  end

  it 'renames namespace symbol with proper range' do
    host = Solargraph::LanguageServer::Host.new
    host.start
    host.open(temp_file_url, %(
      module Namespace; end
      class Namespace::ExampleClass
      end
      obj = Namespace::ExampleClass.new
    ), 1)
    rename = described_class.new(host, {
                                   'id' => 1,
                                   'method' => 'textDocument/rename',
                                   'params' => {
                                     'textDocument' => {
                                       'uri' => temp_file_url
                                     },
                                     'position' => {
                                       'line' => 2,
                                       'character' => 12
                                     },
                                     'newName' => 'Nameplace'
                                   }
                                 })
    # keep this from syncing a bunch of bundle gems in background
    library = host.library_for(temp_file_url)
    library.stop
    changes = process_changes(rename, temp_file_url)
    expect(changes.length).to eq(3)
    expect(changes.first[:range][:start][:character]).to eq(13)
    expect(changes.first[:range][:end][:character]).to eq(22)
  ensure
    host.fully_stop
  end
end
