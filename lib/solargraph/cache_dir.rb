# frozen_string_literal: true

require 'fileutils'
require 'rbs'

module Solargraph
  module CacheDir
    module_function

    # The base directory for cached YARD documentation and serialized pins.
    #
    # @return [String]
    def base_dir
      ENV['SOLARGRAPH_CACHE'] ||
        (ENV['XDG_CACHE_HOME'] ? File.join(ENV['XDG_CACHE_HOME'], 'solargraph') : nil) ||
        File.join(Dir.home, '.cache', 'solargraph')
    end

    # The working directory for the current Ruby, RBS, and Solargraph versions.
    #
    # @return [String]
    def work_dir
      File.join(base_dir, "ruby-#{RUBY_VERSION}", "rbs-#{RBS::VERSION}", "solargraph-#{Solargraph::VERSION}")
    end

    # The current gem directory.
    #
    # @return [String]
    def gem_dir
      File.join(work_dir, 'gems')
    end

    # The current stdlib directory.
    #
    # @return [String]
    def stdlib_dir
      File.join(work_dir, 'stdlib')
    end

    # The current RBS collection directory.
    #
    # @return [String]
    def rbs_dir
      File.join(work_dir, 'rbs')
    end

    # The directory for the current YARD version.
    #
    # @return [String]
    def yard_dir
      File.join(base_dir, "yard-#{YARD::VERSION}")
    end

    # A plugin decides what YARD extracts, so pins built under one set of
    # them must not be served to a workspace declaring another. Callers
    # reach this with either spelling of a plugin name, `activesupport-
    # concern` or the `yard-activesupport-concern` its gem carries.
    #
    # @param yard_plugins [Array<String>]
    # @return [String]
    def yard_plugins_key yard_plugins
      return 'no-plugins' if yard_plugins.empty?

      yard_plugins.map { |plugin| yard_plugin_segment(plugin) }.sort.uniq.join('-')
    end

    # An upgraded plugin extracts different documentation from the same
    # source, so its version belongs in the key alongside its name.
    #
    # @param plugin [String]
    # @return [String]
    def yard_plugin_segment plugin
      name = plugin.delete_prefix('yard-')
      spec = Gem.loaded_specs["yard-#{name}"] || Gem::Specification.find_by_name("yard-#{name}")
      "#{name}-#{spec.version}"
    rescue Gem::MissingSpecError
      name
    end
    private_class_method :yard_plugin_segment

    def clear
      FileUtils.rm_rf base_dir
    end
  end
end
