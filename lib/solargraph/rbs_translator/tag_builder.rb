# frozen_string_literal: true

module Solargraph
  module RbsTranslator
    # Render RBS type objects as Solargraph type tags.
    #
    module TagBuilder
      module_function

      # @param type [RBS::Types::Bases::Base]
      # @return [String]
      def type_to_tag type
        case type
        when RBS::Types::Optional
          "#{type_to_tag(type.type)}, nil"
        when RBS::Types::Bases::Bool
          'Boolean'
        when RBS::Types::Tuple
          "Array(#{type.types.map { |t| type_to_tag(t) }.join(', ')})"
        when RBS::Types::Literal
          type.literal.inspect
        when RBS::Types::Union
          type.types.map { |t| type_to_tag(t) }.join(', ')
        when RBS::Types::Record
          # @todo Better record support
          'Hash'
        when RBS::Types::Bases::Nil
          'nil'
        when RBS::Types::Bases::Void
          'void'
        when RBS::Types::Variable
          "#{Solargraph::ComplexType::GENERIC_TAG_NAME}<#{type.name}>"
        when RBS::Types::Bases::Self, RBS::Types::Bases::Instance
          'self'
        when RBS::Types::Bases::Top
          # `Top` is the most super superclass
          'BasicObject'
        when RBS::Types::Intersection
          type.types.map { |member| type_to_tag(member) }.join(', ')
        when RBS::Types::Proc
          'Proc'
        when RBS::Types::ClassInstance, RBS::Types::Alias, RBS::Types::Interface
          # `Alias` is a top-level type alias, e.g., 'bool' in "type bool = true | false"
          # @todo ensure these get resolved after processing all aliases
          # @todo handle recursive aliases
          #
          # `Interface represents a mix-in module which can be considered a
          # subtype of a consumer of it
          #
          type_tag(type.name, type.args)
        when RBS::Types::ClassSingleton
          # e.g., singleton(String)
          type_tag(type.name)
        when RBS::Types::Bases::Any, RBS::Types::Bases::Bottom
          # `Bottom`` is used in contexts where nothing will ever return
          # - e.g., it could be the return type of 'exit()' or 'raise'
          # @todo define a specific bottom type and use it to
          #   determine dead code
          #
          'undefined'
        else
          Solargraph.logger.warn "Unrecognized RBS type: #{type.class} at #{type.location}"
          'undefined'
        end
      end

      # @param type_name [RBS::TypeName]
      # @param type_args [Enumerable<RBS::Types::Bases::Base>]
      # @return [String]
      def type_tag(type_name, type_args = [])
        build_type(type_name, type_args).tags
      end

      # @param type_name [RBS::TypeName]
      # @param type_args [Enumerable<RBS::Types::Bases::Base>]
      # @return [ComplexType::UniqueType]
      def build_type(type_name, type_args = [])
        base = RBS_TO_YARD_TYPE[type_name.relative!.to_s] || type_name.relative!.to_s
        params = type_args.map { |a| type_to_tag(a) }.map do |t|
          ComplexType.try_parse(t)
        end
        if base == 'Hash' && params.length == 2
          ComplexType::UniqueType.new(base, [params.first], [params.last], rooted: true, parameters_type: :hash)
        else
          ComplexType::UniqueType.new(base, [], params.reject(&:undefined?), rooted: true, parameters_type: :list)
        end
      end
    end
  end
end
