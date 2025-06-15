# frozen_string_literal: true

require 'rbs'

module Solargraph
  class RbsMap
    # Ruby core pins
    #
    class CoreMap
      include Conversions

      def resolved?
        true
      end

      FILLS_DIRECTORY = File.join(File.dirname(__FILE__), '..', '..', '..', 'rbs', 'fills')

      def pins
        return @pins if @pins

        @pins = []
        cache = PinCache.deserialize_core
        if cache
          @pins.replace cache
        else
          RBS::Environment.from_loader(loader).resolve_type_names
          load_environment_to_pins(loader)
          @pins.concat RbsMap::CoreFills::ALL
          processed = ApiMap::Store.new(@pins).pins.reject { |p| p.is_a?(Solargraph::Pin::Reference::Override) }
          @pins.replace processed

          PinCache.serialize_core @pins
        end
        @pins
      end

      def loader
        @loader ||= begin
                      loader = RBS::EnvironmentLoader.new(repository: RBS::Repository.new(no_stdlib: false))
                      loader.add(path: Pathname(FILLS_DIRECTORY))
                      loader
                    end
      end
    end
  end
end
