# frozen_string_literal: true

# Type stub for the optional `vernier` profiling gem used by `solargraph
# profile`. The gem is not a dependency: the command requires it lazily and
# prints an install hint if it is missing, so its constants are otherwise
# unresolvable when typechecking this project.
#
# This directory is excluded from the packaged gem and is only mapped when
# Solargraph indexes this workspace.
module Vernier
  # @param out [String]
  # @param hooks [Array<Symbol>]
  # @yieldreturn [void]
  # @return [void]
  def self.profile out:, hooks: [], &block; end
end
