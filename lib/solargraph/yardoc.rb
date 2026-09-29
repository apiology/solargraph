# frozen_string_literal: true

require 'open3'
require 'fileutils'

module Solargraph
  # Methods for caching and loading YARD documentation for gems.
  #
  module Yardoc
    module_function

    # A gem gets one yardoc per set of plugins it was built under, so a
    # workspace declaring a different set builds its own rather than reading
    # one whose contents it never asked for.
    #
    # @param metagem [Metagem]
    # @param yard_plugins [Array<String>]
    # @return [String]
    def path_for metagem, yard_plugins
      File.join(CacheDir.yard_dir, "#{metagem.cache_name}-#{CacheDir.yard_plugins_key(yard_plugins)}.yardoc")
    end

    # Every yardoc built for a gem, whichever plugins built it.
    #
    # @param metagem [Metagem]
    # @return [Array<String>]
    def paths_for metagem
      Dir.glob(File.join(CacheDir.yard_dir, "#{metagem.cache_name}-*.yardoc"))
    end

    # Build a gem's yardoc into a given path.
    #
    # @param gem_yardoc_path [String] the path to the yardoc cache of a particular gem
    # @param yard_plugins [Array<String>] The names of YARD plugins to use.
    # @param metagem [Metagem]
    # @return [void]
    def build_docs gem_yardoc_path, yard_plugins, metagem
      return if docs_built?(gem_yardoc_path)

      unless Dir.exist? metagem.full_path
        # Can happen in at least some (old?) RubyGems versions when we
        # have a gemspec describing a standard library like bundler.
        #
        # https://github.com/apiology/solargraph/actions/runs/17650140201/job/50158676842?pr=10
        Solargraph.logger.info { "Bad info from gemspec - #{metagem.full_path} does not exist" }
        return
      end

      Solargraph.logger.info "Caching yardoc for #{metagem.cache_name}"
      FileUtils.mkdir_p File.dirname(gem_yardoc_path)
      cmd = ['yardoc', '--db', gem_yardoc_path, '--no-output', '--plugin', 'solargraph']
      yard_plugins.each { |plugin| cmd.push('--plugin', plugin) }
      Solargraph.logger.debug "Running: #{cmd.inspect}"
      output, status = Open3.capture2e(*cmd, chdir: metagem.full_path)
      return if status.success?

      Solargraph.logger.warn { "YARD failed running #{cmd.inspect} in #{metagem.full_path}" }
      Solargraph.logger.info output
    # @todo Ignore missing metagems for now. We need to figure out why this
    #   happens in GitHub actions.
    rescue Errno::ENOENT => _e
      Solargraph.logger.warn "Gem #{metagem.name} #{metagem.version} not found at #{metagem.full_path}"
    end

    # @param metagem [Metagem]
    # @param yard_plugins [Array<String>]
    # @param force [Boolean]
    # @return [void]
    def cache metagem, yard_plugins, force: false
      path = path_for(metagem, yard_plugins)
      FileUtils.rm_rf path if force
      build_docs path, yard_plugins, metagem
    end

    # Delete every yardoc built for the gem, so a rebuild is not served a
    # yardoc some other plugin set left behind.
    #
    # @param metagem [Metagem]
    # @return [void]
    def uncache metagem
      paths_for(metagem).each { |path| FileUtils.rm_rf path }
    end

    # @param gem_yardoc_path [String] the path to the yardoc cache of a particular gem
    def docs_built? gem_yardoc_path
      File.exist?(File.join(gem_yardoc_path, 'complete'))
    end

    # @param metagem [Metagem]
    # @param yard_plugins [Array<String>]
    def cached? metagem, yard_plugins
      docs_built? path_for(metagem, yard_plugins)
    end
    alias exist? cached?

    # True if another process is currently building the yardoc cache.
    #
    # @param gem_yardoc_path [String] the path to the yardoc cache of a particular gem
    def processing? gem_yardoc_path
      File.exist?(File.join(gem_yardoc_path, 'processing'))
    end

    # Load a gem's yardoc cache and return its code objects.
    #
    # @note This method modifies the global YARD registry.
    #
    # @param gem_yardoc_path [String] the path to the yardoc cache of a particular gem
    # @return [Array<YARD::CodeObjects::Base>]
    def load! gem_yardoc_path
      YARD::Registry.load! gem_yardoc_path
      YARD::Registry.all
    end

    # @param gem_yardoc_path [String] the path to the yardoc cache of a particular gem
    # @param metagem [Metagem]
    # @return [Array<Pin::Base>]
    def build_pins gem_yardoc_path, metagem
      YardMap::Mapper.new(load!(gem_yardoc_path), metagem).map
    end
  end
end
