# frozen_string_literal: true

require 'fileutils'

module Solargraph
  module Collection
    # The base class for cacheable pin collections. Subclasses need to
    # implement #pins and #cache_file.
    #
    # @!method pins
    #   The array of pins for this collection.
    #   @abstract
    #   @return [Array<Pin::Base>]
    # @!method cache_file
    #   The file that will store serialized pins.
    #   @abstract
    #   @return [String]
    class Base
      # @return [Array<Pin::Base>]
      def load
        mem_cache_pins || file_cache_pins || generate_pin_caches
      end

      # @return [Array<Pin::Base>]
      def self.load(...)
        new(...).load
      end

      def self.uncache(...)
        cache_file = new(...).cache_file
        FileUtils.rm_rf cache_file
        Collection.mem_cache.delete cache_file
      end

      private

      def mem_cache_pins
        Collection.mem_cache[cache_file]
      end

      def file_cache_pins
        Marshal.load(File.read(cache_file, mode: 'rb')) if File.exist?(cache_file) # rubocop:disable Security/MarshalLoad
      end

      def generate_pin_caches
        Collection.mem_cache[cache_file] = pins
        serial = Marshal.dump(pins)
        FileUtils.mkdir_p File.dirname(cache_file)
        # Write to a temp file in the same directory and rename into place
        # (rename is atomic on the same filesystem) so that concurrent
        # readers/writers - e.g. multiple parallel_tests worker processes,
        # or the threads in Collection::Gem.load_all, caching the same gem
        # for the first time - never observe a partially-written file.
        tmp = "#{cache_file}.#{Process.pid}.#{Thread.current.object_id}.tmp"
        File.write tmp, serial, mode: 'wb'
        File.rename tmp, cache_file
        pins
      end
    end
  end
end
