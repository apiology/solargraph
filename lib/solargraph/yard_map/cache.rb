# frozen_string_literal: true

module Solargraph
  class YardMap
    class Cache
      def initialize
        # @type [Hash{String => Array<Solargraph::Pin::Base>}]
        @path_pins = {}
      end

      # @param path [String]
      # @param pins [Array<Solargraph::Pin::Base>]
      # @return [Array<Solargraph::Pin::Base>]
      def set_path_pins path, pins
        @path_pins[path] = pins
      end

      # @param path [String]
      # @return [Array<Solargraph::Pin::Base>]
      # @sg-ignore Declared return type ::Array<::Solargraph::Pin::Base> does not match inferred type ::Array<::Solargraph::Pin::Base>, nil for Solargraph::YardMap::Cache#get_path_pins
      def get_path_pins path
        @path_pins[path]
      end
    end
  end
end
