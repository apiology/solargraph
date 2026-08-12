# frozen_string_literal: true

module Solargraph
  module Convention
    class Gemfile < Base
      def local source_map
        # @sg-ignore Wrong argument type for File.basename: file_name expected String, _ToStr, _ToPath, received String, nil
        return EMPTY_ENVIRON unless File.basename(source_map.filename) == 'Gemfile'
        @local ||= Environ.new(
          requires: ['bundler'],
          domains: ['Bundler::Dsl']
        )
      end
    end
  end
end
