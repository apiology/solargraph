# frozen_string_literal: true

module Solargraph
  module LanguageServer
    module Message
      module Workspace
        class WorkspaceSymbol < Solargraph::LanguageServer::Message::Base
          include Solargraph::LanguageServer::UriHelpers

          def process
            pins = host.query_symbols(params['query'])
            info = pins.map do |pin|
              # @sg-ignore Unresolved call to filename on Solargraph::Location, nil
              uri = file_to_uri(pin.best_location.filename)
              {
                name: pin.path,
                containerName: pin.namespace,
                kind: pin.symbol_kind,
                location: {
                  uri: uri,
                  # @sg-ignore Unresolved call to range on Solargraph::Location, nil
                  range: pin.best_location.range.to_hash
                },
                deprecated: pin.deprecated?
              }
            end
            set_result info
          end
        end
      end
    end
  end
end
