# frozen_string_literal: true

require 'fileutils'
require 'rbs'

module Solargraph
  # The cache directories. Plugins can change the pins mapped from gem
  # source, so each workspace has its own CacheDir, which keys the gem
  # directory on the plugins that workspace loaded.
  #
  class CacheDir
    # The base directory for cached YARD documentation and serialized pins.
    #
    # @return [String]
    # @sg-ignore An || chain ending in a String is inferred as nilable
    def self.base_dir
      ENV['SOLARGRAPH_CACHE'] ||
        (ENV['XDG_CACHE_HOME'] ? File.join(ENV['XDG_CACHE_HOME'], 'solargraph') : nil) ||
        File.join(Dir.home, '.cache', 'solargraph')
    end

    # The working directory for the current Ruby, RBS, and Solargraph versions.
    #
    # @return [String]
    def self.work_dir
      File.join(base_dir, "ruby-#{RUBY_VERSION}", "rbs-#{RBS::VERSION}", "solargraph-#{Solargraph::VERSION}")
    end

    # The gem name and version of each plugin added to this cache
    # directory.
    #
    # @return [Hash{String => String, nil}]
    attr_reader :plugins

    # What to require to load {plugins} again in another process, such as
    # the cache subprocess, so that it writes to the same {gem_dir}.
    #
    # @return [Array<String>]
    attr_reader :plugin_requires

    def initialize
      @plugins = {}
      @plugin_requires = []
    end

    # The gem directory for {plugins}. Each set of plugin versions gets its
    # own.
    #
    # @return [String]
    def gem_dir
      return File.join(CacheDir.work_dir, 'gems') if plugins.empty?
      key = plugins.sort.map { |name, version| [name, version].compact.join('-') }.join('+')
      File.join(CacheDir.work_dir, "gems-#{key.tr(File::SEPARATOR, '_')}")
    end

    # @param name [String] the require path of a plugin that loaded
    # @return [void]
    def add_plugin name
      # @sg-ignore Unresolved call to name on Gem::BasicSpecification, Hash{String => Gem::BasicSpecification}
      spec = Gem.loaded_specs.each_value.find { |s| s.name == name || s.contains_requirable_file?(name) }
      plugins[spec&.name || name] = spec&.version&.to_s
      plugin_requires.push name unless plugin_requires.include?(name)
    end

    # The current stdlib directory.
    #
    # @return [String]
    def self.stdlib_dir
      File.join(work_dir, 'stdlib')
    end

    # The current RBS collection directory.
    #
    # @return [String]
    def self.rbs_dir
      File.join(work_dir, 'rbs')
    end

    # The directory for the current YARD version.
    #
    # @return [String]
    def self.yard_dir
      File.join(base_dir, "yard-#{YARD::VERSION}", "yard-activesupport-concern-#{YARD::ActiveSupport::Concern::VERSION}")
    end

    # @return [void]
    def self.clear
      FileUtils.rm_rf base_dir
    end
  end
end
