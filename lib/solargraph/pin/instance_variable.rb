# frozen_string_literal: true

module Solargraph
  module Pin
    class InstanceVariable < BaseVariable
      # @return [ComplexType, ComplexType::UniqueType, nil] The binder of
      #   an instance variable declared by its namespace, e.g. with RBS or
      #   a `@type @name [Type]` tag in a module body.
      attr_reader :declared_binder

      # @param declared_binder [ComplexType, ComplexType::UniqueType, nil]
      # @param assignment [Parser::AST::Node, nil]
      # @param assignments [Array<Parser::AST::Node>]
      # @param mass_assignment [::Array(Parser::AST::Node, Integer), nil]
      # @param presence [Range, nil]
      # @param return_type [ComplexType, nil]
      # @param intersection_return_type [ComplexType, nil]
      # @param exclude_return_type [ComplexType, nil]
      # @param [Hash{Symbol => Object}] splat
      def initialize declared_binder: nil, assignment: nil, assignments: [], mass_assignment: nil,
                     presence: nil, return_type: nil, intersection_return_type: nil,
                     exclude_return_type: nil, **splat
        super(assignment: assignment, assignments: assignments, mass_assignment: mass_assignment,
              presence: presence, return_type: return_type,
              intersection_return_type: intersection_return_type,
              exclude_return_type: exclude_return_type, **splat)
        @declared_binder = declared_binder
      end

      def declared?
        !declared_binder.nil?
      end

      # @sg-ignore Need to add nil check here
      # @return [ComplexType, ComplexType::UniqueType]
      def binder
        # @sg-ignore Need to add nil check here
        declared_binder || closure.binder
      end

      # @return [::Symbol]
      def scope
        binder.scope
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

      # @param other [self]
      # @param attrs [Hash{Symbol => Object}]
      #
      # @return [self]
      def combine_with other, attrs = {}
        super(other, { declared_binder: declared_binder || other.declared_binder }.merge(attrs))
      end

      # @param other_closure [Pin::Closure]
      # @param other_loc [Location]
      def visible_at? other_closure, other_loc
        declared? || super
      end
    end
  end
end
