# frozen_string_literal: true

require 'set'

module Solargraph
  # @todo This class might need a way to track changes to the repo, e.g.,
  #   bundle or dependency updates
  #
  class External
    # @return [String]
    attr_reader :directory

    # @return [Array<String>]
    attr_reader :requires

    # The YARD plugins the workspace declares. Gem pins are cached per set,
    # so a workspace is never served pins built under plugins it dropped.
    #
    # @return [Array<String>]
    attr_reader :yard_plugins

    # @param directory [String]
    # @param requires [Array<String>]
    # @param yard_plugins [Array<String>]
    def initialize directory, requires, yard_plugins = []
      @repo = Repo.new(directory)
      @directory = directory
      @requires = requires
      @yard_plugins = yard_plugins
      update!
    end

    def unresolved_requires
      @unresolved_requires ||= []
    end

    def unresolved_dependencies
      @unresolved_dependencies ||= []
    end

    def loaded_gems
      @loaded_gems ||= Set.new
    end

    def unloaded_gems
      @unloaded_gems ||= Set.new
    end

    def pins
      @pins ||= []
    end

    # @return [Integer] incremented whenever the external pin set is rebuilt
    def generation
      @generation ||= 0
    end

    # @param new_requires [Array<String>]
    # @param new_yard_plugins [Array<String>]
    # @return [Boolean]
    def update new_requires, new_yard_plugins = []
      return false if requires == new_requires && yard_plugins == new_yard_plugins && !cache_changed?

      requires.replace new_requires
      yard_plugins.replace new_yard_plugins
      update!
      true
    end

    # @return [Array<String>]
    def rbs_collection_paths
      @rbs_collection_paths ||= read_rbs_collection_paths
    end

    # @return [String, nil]
    def rbs_collection_config_path
      # @todo Get rid of the '*' case
      @rbs_collection_config_path ||= unless directory.nil? || directory.empty? || directory == '*'
                                        yaml_file = File.join(directory, 'rbs_collection.yaml')
                                        yaml_file if File.file?(yaml_file)
                                      end
    end

    private

    def update!
      @generation = generation + 1
      clear_all
      load_requires
      load_rbs_collection
    end

    def cache_changed?
      unloaded_gems.any? { |gem| Collection::Gem.cached?(gem, yard_plugins) }
    end

    def load_requires
      bundler_require = false

      requires.uniq.each do |path|
        if path == 'bundler/require'
          bundler_require = true
        end
        if RbsMap::Stdlib.has?(path)
          pins.concat Collection::Stdlib.load(path)
        else
          metagem = @repo.find_by_path(path)
          next unresolved_requires.push(path) unless metagem
          process_gem metagem
        end
      end

      return unless bundler_require

      @repo.find_by_group(:default).each { |metagem| process_gem metagem }
    end

    def load_rbs_collection
      rbs_collection_pins = rbs_collection_paths.flat_map { |path| Collection::Rbs.load(path) }
      pins.replace RbsMap::Helpers.combine(pins, rbs_collection_pins)
    end

    def clear_all
      pins.clear
      unresolved_requires.clear
      unresolved_dependencies.clear
      loaded_gems.clear
      unloaded_gems.clear
    end

    def process_gem metagem
      return if loaded_gems.include?(metagem) || unloaded_gems.include?(metagem)

      if metagem.cacheable?
        if Collection::Gem.cached?(metagem, yard_plugins)
          loaded_gems.add metagem
          pins.concat Collection::Gem.load(metagem, yard_plugins)
        else
          unloaded_gems.add metagem
        end
      else
        loaded_gems.add metagem
        pins.concat Collection::Gem.load(metagem, yard_plugins)
      end
      load_dependencies metagem
    end

    def load_dependencies parent
      parent.dependencies.each do |name|
        next if loaded_gems.map(&:name).include?(name) || unloaded_gems.map(&:name).include?(name)
        metagem = @repo.find_by_name(name)
        next unresolved_dependencies.push(name) unless metagem
        process_gem metagem
      end
    end

    # @return [Array<String>]
    def read_rbs_collection_paths
      return [] unless rbs_collection_config_path

      yaml = YAML.load_file(rbs_collection_config_path)
      [File.expand_path(yaml.fetch('path'), directory)].concat(
        yaml.fetch('sources', [])
            .select { |source| source['type'] == 'local' && source['path'] }
            .map { |source| File.expand_path(source['path'], directory) }
      ).compact
    end
  end
end
