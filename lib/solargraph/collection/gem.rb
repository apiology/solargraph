# frozen_string_literal: true

module Solargraph
  module Collection
    # Cacheable gem pins.
    #
    class Gem < Base
      include Logging

      attr_reader :metagem

      # @return [Array<String>]
      attr_reader :yard_plugins

      # @param metagem [Metagem]
      # @param yard_plugins [Array<String>]
      def initialize metagem, yard_plugins = []
        super()
        @metagem = metagem
        @yard_plugins = yard_plugins
      end

      def cache_file
        File.join CacheDir.gem_dir, "#{metagem.cache_name}-#{CacheDir.yard_plugins_key(yard_plugins)}.ser"
      end

      def load
        return pins unless metagem.cacheable?
        super
      end

      def pins
        @pins ||= if metagem.cacheable?
                    cacheable_pins
                  else
                    uncacheable_pins
                  end
      end

      # @param metagem [Metagem]
      # @param yard_plugins [Array<String>]
      def self.cached? metagem, yard_plugins = []
        metagem.cacheable? && File.exist?(new(metagem, yard_plugins).cache_file)
      end

      # Drop every artifact cached for the gem, whichever plugins built it.
      # A rebuild that reused one would serve documentation the workspace
      # never asked for.
      #
      # @param metagem [Metagem]
      # @return [void]
      def self.uncache metagem
        return unless metagem.cacheable?

        Dir.glob(File.join(CacheDir.gem_dir, "#{metagem.cache_name}-*.ser")).each do |file|
          FileUtils.rm_rf file
          Collection.mem_cache.delete file
        end
        Yardoc.uncache metagem
      end

      private

      def cacheable_pins
        gem_yardoc_path = Yardoc.path_for(metagem, yard_plugins)
        Yardoc.build_docs(gem_yardoc_path, yard_plugins, metagem)
        yard_pins = Yardoc.docs_built?(gem_yardoc_path) ? Yardoc.build_pins(gem_yardoc_path, metagem) : []
        rbs_pins = RbsMap::Gem.pins(metagem)
        RbsMap::Helpers.combine(yard_pins, rbs_pins)
      end

      def uncacheable_pins
        files = metagem.require_paths.flat_map { |path| Dir.glob(File.join(metagem.full_path, path, '**', '*.rb')) }
        source_maps = files.map { |file| Solargraph::SourceMap.load(file) }
        source_pins = source_maps.flat_map(&:pins)
        rbs_pins = RbsMap::Gem.pins(metagem)
        RbsMap::Helpers.combine(source_pins, rbs_pins)
      end
    end
  end
end
