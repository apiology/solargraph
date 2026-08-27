# frozen_string_literal: true

module Solargraph
  module Pin
    # DuckMethod pins are used to add completion items for type tags that
    # use duck typing, e.g., `@param file [#read]`.
    #
    class DuckMethod < Pin::Method
      # A DuckMethod is a synthetic placeholder for "whatever type responds
      # to this method" - it isn't a real method in #closure's namespace, so
      # it has no ancestor chain of its own. #typify_from_super otherwise
      # walks #closure's real method stack looking for a same-named,
      # same-scope method to inherit a type from; since #closure is the
      # call site (e.g. the method whose body calls clazz.new), and most
      # classes have their own unrelated #new inherited from Class, that
      # walk finds it and returns the call site's own enclosing class - a
      # confidently wrong type, not the unresolved one this method should
      # produce when its own signature can't answer the call.
      #
      # @param _api_map [ApiMap]
      # @return [Array<Pin::Method>]
      def rest_of_stack _api_map
        []
      end
    end
  end
end
