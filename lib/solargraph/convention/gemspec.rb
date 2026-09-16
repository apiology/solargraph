# frozen_string_literal: true

module Solargraph
  module Convention
    class Gemspec < Base
      def local source_map
        # @sg-ignore Wrong argument type for File.basename: file_name expected String, _ToStr, _ToPath, received String, nil
        return Convention::Base::EMPTY_ENVIRON unless File.basename(source_map.filename).end_with?('.gemspec')
        @local ||= Environ.new(
          requires: ['rubygems'],
          pins: [
            Solargraph::Pin::Reference::Override.from_comment(
              'Gem::Specification.new',
              %(
@yieldparam [self]
              ),
              source: :gemspec
            )
          ]
        )
      end
    end
  end
end
