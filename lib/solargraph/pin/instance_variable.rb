# frozen_string_literal: true

module Solargraph
  module Pin
    class InstanceVariable < BaseVariable
      # @sg-ignore Need to add nil check here
      # @return [ComplexType, ComplexType::UniqueType]
      def binder
        # @sg-ignore Need to add nil check here
        closure.binder
      end

      # @sg-ignore Need to add nil check here
      # @return [::Symbol]
      def scope
        # @sg-ignore Need to add nil check here
        closure.binder.scope
      end

      # @return [ComplexType]
      def context
        @context ||= begin
          result = super
          if scope == :class
            ComplexType.parse("::Class<#{result.rooted_namespace}>")
          else
            result.reduce_class_type
          end
        end
      end

      # @param other [InstanceVariable]
      def nearly? other
        super && binder == other.binder
      end

      # BaseVariable#visible_at? requires the assignment and the read
      # to be in the same file. That's correct whenever +presence+ is
      # set (a flow-sensitive-narrowed range is only comparable to
      # another position in the same file), but a plain, unnarrowed
      # instance variable assignment has no +presence+ and can live in
      # a different file than the read entirely - e.g. an ancestor
      # class's method assigning the ivar, and a descendant class
      # defined in its own file reading it. Only enforce the same-file
      # requirement when +presence+ actually needs it.
      #
      # @param other_closure [Pin::Closure]
      # @param other_loc [Location]
      def visible_at? other_closure, other_loc
        return false if presence && location&.filename != other_loc.filename
        return false if presence && !presence.include?(other_loc.range.start)

        visible_in_closure?(other_closure)
      end

      private

      # See if this variable is visible within 'viewing_closure'.
      #
      # BaseVariable's implementation walks the *lexical* nesting of
      # +viewing_closure+ (method -> enclosing class/module -> ...)
      # looking for a closure whose namespace matches this pin's own
      # namespace, and gives up (returns false) once it reaches a
      # Namespace pin with no match. That walk only reflects lexical
      # nesting, not class inheritance, so it incorrectly hides an
      # instance variable pin created in an ancestor class's method
      # from a descendant class's method: the descendant's enclosing
      # namespace is never lexically nested inside the ancestor's.
      #
      # #get_instance_variable_pins already restricts candidate pins
      # to the reading namespace and its ancestors before
      # ApiMap#var_at_location ever calls this method, so reaching a
      # Namespace pin here with no closer (lexical or flow-sensitive)
      # match means the pin is visible via inheritance - accept it
      # instead of rejecting it.
      #
      # @param viewing_closure [Pin::Closure]
      # @return [Boolean]
      def visible_in_closure? viewing_closure
        return false if closure.nil?

        # if we're declared at top level, we can't be seen from within
        # methods declared tere

        return false if viewing_closure.is_a?(Pin::Method) && closure.context.tags == 'Class<>'

        return true if viewing_closure.binder.namespace == closure.binder.namespace

        return true if viewing_closure.return_type == closure.context

        # Unlike BaseVariable, don't stop here: an instance variable
        # assigned in an ancestor class's method is still visible from
        # a descendant class's method, and #get_instance_variable_pins
        # already guarantees any candidate pin that reaches this point
        # comes from the reading namespace or one of its ancestors.
        return true if viewing_closure.is_a?(Pin::Namespace)

        parent_of_viewing_closure = viewing_closure.closure

        return false if parent_of_viewing_closure.nil?

        visible_in_closure?(parent_of_viewing_closure)
      end
    end
  end
end
