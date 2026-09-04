# frozen_string_literal: true

module Solargraph
  module LanguageServer
    module Message
      module TextDocument
        class SignatureHelp < TextDocument::Base
          # @return [void]
          def process
            line = params['position']['line']
            col = params['position']['character']
            suggestions = host.signatures_at(params['textDocument']['uri'], line, col)
            set_result({
                         signatures: suggestions.flat_map(&:signature_help)
                       })
          rescue FileNotFoundError => e
            Logging.logger.warn "[#{e.class}] #{e.message}"
            # @sg-ignore Need to add nil check here
            Logging.logger.warn e.backtrace.join("\n")
            # @sg-ignore Wrong argument type for Solargraph::LanguageServer::Message::Base#set_result: data expected Hash, Array, nil, received NilClass
            set_result nil
          end
        end
      end
    end
  end
end
