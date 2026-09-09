# frozen_string_literal: true

module Solargraph
  module Convention
    class Rakefile < Base
      def local source_map
        # @sg-ignore Wrong argument type for File.basename: file_name expected String, _ToStr, _ToPath, received String, nil
        basename = File.basename(source_map.filename)
        return EMPTY_ENVIRON unless basename.end_with?('.rake') || basename == 'Rakefile'

        @local ||= Environ.new(
          requires: ['rake'],
          domains: ['Rake::DSL']
        )
      end
    end
  end
end
