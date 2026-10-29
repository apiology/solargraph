# frozen_string_literal: true

module Solargraph
  module LanguageServer
    module Message
      module Extended
        class Document < Base
          def process
            api_map, pins = host.document(params['query'])
            page = Solargraph::Page.new(host.options['viewsPath'])
            content = page.render('document', layout: true, locals: { api_map: api_map, pins: pins })
            set_result(
              content: content
            )
          end
        end
      end
    end
  end
end
