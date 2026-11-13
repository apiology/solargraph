# frozen_string_literal: true

require 'overcommit/hook/pre_commit/solargraph'

module Overcommit
  module Hook
    module PreCommit
      # Runs Overcommit's built-in Solargraph hook, but counts a line as
      # modified only if it differs from the merge base with `base_ref`
      # (default: origin/master), as CI's `overcommit --run --diff` does.
      #
      # The built-in hook diffs against HEAD, so restoring a line to
      # master's content reports master's existing problems on it as
      # errors on modified lines.
      class SolargraphVsBase < Solargraph
        def modified_lines_in_file file
          return super unless @context.is_a?(Overcommit::HookContext::PreCommit) && merge_base

          @modified_lines_vs_base ||= {}
          @modified_lines_vs_base[file] ||=
            Overcommit::GitRepo.extract_modified_lines(file, staged: true, refs: merge_base)
        end

        private

        # @return [String, nil]
        def merge_base
          return @merge_base if defined?(@merge_base)

          result = execute(['git', 'merge-base', 'HEAD', @config.fetch('base_ref', 'origin/master')])
          @merge_base = result.success? ? result.stdout.strip : nil
        end
      end
    end
  end
end
