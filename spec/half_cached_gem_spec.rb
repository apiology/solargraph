# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'

# A gem's pins come from its YARD documentation and from RBS, held as two
# halves and a merge of the two. Which halves a workspace happens to find
# should not decide what it is told the gem's types are.
describe Solargraph::ApiMap do
  # RBS gives this method a return type; YARD gives it only a location.
  let(:path) { 'RBS::EnvironmentLoader#core_root' }

  # @return [String]
  def cache_dir
    ENV['SOLARGRAPH_CACHE'] || File.join(Dir.home, '.cache', 'solargraph')
  end

  # @return [Array<String>] the gem's cache entries under this Solargraph
  def cached_entries
    Dir.glob(File.join(cache_dir, '**', '*rbs-*'))
       .select { |entry| File.file?(entry) && entry.include?("solargraph-#{Solargraph::VERSION}") }
  end

  # Pins are memoized for the life of a process, so each state is asked in one
  # of its own.
  #
  # @param directory [String]
  # @return [String] the return type the workspace reports
  def return_type_in directory
    script = "require 'solargraph'; " \
             "puts Solargraph::ApiMap.load_with_cache(#{directory.inspect}, nil)" \
             ".get_path_pins(#{path.inspect}).first&.return_type.to_s"
    output, status = Open3.capture2e(RbConfig.ruby, '-e', script)
    raise output unless status.success?

    output.lines.last.chomp
  end

  # Put the cache back to the named halves of a run that built all of them.
  #
  # @param whole [Hash{String => String}] every entry that run wrote
  # @param keep [Array<String>] the cache subdirectories to restore
  # @return [void]
  def restore whole, keep
    cached_entries.each { |entry| File.delete(entry) }
    whole.each do |entry, content|
      next unless keep.any? { |half| entry.include?("/#{half}/") }

      FileUtils.mkdir_p File.dirname(entry)
      File.binwrite entry, content
    end
  end

  before { capture_both { Solargraph::Shell.new.uncache('rbs') } }

  it 'gives a gem the same types whichever half of its cache it finds' do
    pending 'https://github.com/apiology/solargraph/pull/103'
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, 'app.rb'), "require 'rbs'\n")

      both = return_type_in(directory)
      whole = cached_entries.to_h { |entry| [entry, File.binread(entry)] }

      restore whole, %w[yard]
      yard_only = return_type_in(directory)
      restore whole, %w[rbs]
      rbs_only = return_type_in(directory)

      expect([yard_only, rbs_only]).to eq([both, both])
    end
  end
end
