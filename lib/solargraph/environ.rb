# frozen_string_literal: true

module Solargraph
  # A collection of additional data, such as map pins and required paths, that
  # can be added to an ApiMap.
  #
  # Conventions are used to add Environs.
  #
  class Environ
    # @return [Array<String>]
    attr_reader :requires

    # @return [Array<String>]
    attr_reader :domains

    # @return [Array<Pin::Base>]
    attr_reader :pins

    # @return [Array<String>]
    attr_reader :yard_plugins

    # @return [Array<String>] paths to Ruby scripts to load into the
    #   yardoc subprocess before parsing (see `yardoc -e`), for handlers
    #   that ship with Solargraph itself rather than a separate gem.
    attr_reader :yard_loads

    # @param requires [Array<String>]
    # @param domains [Array<String>]
    # @param pins [Array<Pin::Base>]
    # @param yard_plugins [Array<String>]
    # @param yard_loads [Array<String>]
    def initialize requires: [], domains: [], pins: [], yard_plugins: [], yard_loads: []
      @requires = requires
      @domains = domains
      @pins = pins
      @yard_plugins = yard_plugins
      @yard_loads = yard_loads
    end

    # @return [self]
    def clear
      domains.clear
      requires.clear
      pins.clear
      yard_plugins.clear
      yard_loads.clear
      self
    end

    # @param other [Environ]
    # @return [self]
    def merge other
      domains.concat other.domains
      requires.concat other.requires
      pins.concat other.pins
      yard_plugins.concat other.yard_plugins
      yard_loads.concat other.yard_loads
      self
    end
  end
end
