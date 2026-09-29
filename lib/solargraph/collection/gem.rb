# frozen_string_literal: true

require 'benchmark'
require 'concurrent-ruby'

module Solargraph
  module Collection
    # Cacheable gem pins.
    #
    class Gem < Base
      include Logging

      # Only report timing for batches slow enough to be worth noticing.
      SLOW_BATCH_MS = 500

      attr_reader :metagem

      # @param metagem [Metagem]
      def initialize metagem
        super()
        @metagem = metagem
      end

      def cache_file
        File.join CacheDir.gem_dir, "#{metagem.cache_name}.ser"
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

      def self.cached? metagem
        metagem.cacheable? && File.exist?(new(metagem).cache_file)
      end

      # Build the pin caches for several gems at once, one gem per thread.
      #
      # Each gem is independent - it parses its own yardoc and RBS and
      # writes its own cache file - so the batch scales with the machine
      # rather than running end to end. Building a cold bundle serially is
      # the dominant cost of a first run.
      #
      # @param gems [Enumerable<Metagem>]
      # @param out [IO, StringIO, nil] stream for the timing summary
      # @param rebuild [Boolean] discard existing caches and generate them again
      # @return [void]
      def self.load_all gems, out: nil, rebuild: false
        metagems = gems.to_a
        return if metagems.empty?

        pool_size = Concurrent.processor_count
        pool = Concurrent::FixedThreadPool.new(pool_size)
        time = Benchmark.measure do
          futures = metagems.map do |metagem|
            Concurrent::Promises.future_on(pool, metagem) do |mg|
              uncache mg if rebuild
              load mg
            end
          end
          # #value! re-raises in this thread if any gem failed, matching
          # the serial loop this replaces.
          Concurrent::Promises.zip(*futures).value!
          pool.shutdown
          pool.wait_for_termination
        end

        milliseconds = (time.real * 1000).round
        return unless out && milliseconds > SLOW_BATCH_MS

        out.puts "Built #{metagems.length} gems in #{milliseconds} ms in #{pool_size} threads"
      end

      private

      def cacheable_pins
        code_objects = Yardoc.load!(metagem)
        yard_pins = YardMap::Mapper.new(code_objects, metagem).map
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
