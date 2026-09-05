# frozen_string_literal: true

module Solargraph
  # Convert RBS types to complex types and pins.
  #
  module RbsTranslator
    RBS_TO_YARD_TYPE = {
      'bool' => 'Boolean',
      'string' => 'String',
      'int' => 'Integer',
      'untyped' => '',
      'NilClass' => 'nil'
    }.freeze

    # @param type [RBS::Types::t]
    # @param type_alias_decls [Hash{String => RBS::AST::Declarations::TypeAlias}]
    # @param expanding_aliases [Array<String>] Names of aliases already
    #   being expanded in this call chain, to detect recursive aliases
    # @return [ComplexType]
    def self.to_complex_type type, type_alias_decls: {}, expanding_aliases: []
      tag = type_to_tag(type, type_alias_decls: type_alias_decls, expanding_aliases: expanding_aliases)
      ComplexType.try_parse(tag).force_rooted
    end

    # @param param_type [RBS::Types::Function::Param]
    # @param name [String]
    # @param decl [Symbol]
    # @param closure [Pin::Closure]
    # @param type_alias_decls [Hash{String => RBS::AST::Declarations::TypeAlias}]
    # @return [Pin::Parameter]
    def self.to_parameter_pin param_type, name, decl, closure, type_alias_decls: {}
      return_type = case decl
                    when :restarg
                      RbsTranslator.to_restarg_return_type(param_type.type, type_alias_decls: type_alias_decls)
                    when :kwrestarg
                      RbsTranslator.to_kwrestarg_return_type(param_type.type, type_alias_decls: type_alias_decls)
                    else
                      RbsTranslator.to_complex_type(param_type.type, type_alias_decls: type_alias_decls)
                    end
      Solargraph::Pin::Parameter.new(decl: decl, name: name, closure: closure, return_type: return_type, source: :rbs, type_location: to_sg_location(param_type.location) || closure.type_location)
    end

    # The type of the local variable a restarg is captured into
    # inside the method body - a wrapped Array of its per-element
    # type, e.g. `Array<Integer>` for `*args: Integer`. When the
    # element type isn't known (e.g. an untyped inline `#:`
    # annotation), falls back to a bare, unparameterized Array.
    #
    # @param elem_rbs_type [RBS::Types::t]
    # @param type_alias_decls [Hash{String => RBS::AST::Declarations::TypeAlias}]
    # @return [ComplexType]
    def self.to_restarg_return_type elem_rbs_type, type_alias_decls: {}
      elem_type = RbsTranslator.to_complex_type(elem_rbs_type, type_alias_decls: type_alias_decls)
      return ComplexType.parse('Array') if elem_type.undefined?
      ComplexType.new([ComplexType::UniqueType.new('Array', [], [elem_type], rooted: true, parameters_type: :list)])
    end

    # Likewise, the type of the local variable a kwrestarg is
    # captured into - a wrapped Hash of Symbol to its per-value type.
    #
    # @param elem_rbs_type [RBS::Types::t]
    # @param type_alias_decls [Hash{String => RBS::AST::Declarations::TypeAlias}]
    # @return [ComplexType]
    def self.to_kwrestarg_return_type elem_rbs_type, type_alias_decls: {}
      elem_type = RbsTranslator.to_complex_type(elem_rbs_type, type_alias_decls: type_alias_decls)
      return ComplexType.parse('Hash{Symbol => Object}') if elem_type.undefined?
      ComplexType.new([ComplexType::UniqueType.new('Hash', [ComplexType.try_parse('Symbol')], [elem_type], rooted: true, parameters_type: :hash)])
    end

    # @param method_type [RBS::MethodType, RBS::Types::Block]
    # @param closure [Pin::Closure]
    # @param parameter_names [Array<String>]
    # @param type_alias_decls [Hash{String => RBS::AST::Declarations::TypeAlias}]
    # @return [Array<Pin::Parameter>]
    def self.to_parameter_pins method_type, closure, parameter_names = [], type_alias_decls: {}
      if defined?(RBS::Types::UntypedFunction) && method_type.type.is_a?(RBS::Types::UntypedFunction)
        return [
          Solargraph::Pin::Parameter.new(decl: :restarg, name: 'arg', closure: closure, source: :rbs)
        ]
      end

      arg_num = 0
      params = []
      method_type.type.required_positionals.each do |param|
        # @sg-ignore Unresolved call to name on RBS::Types::Function::Param
        params.push RbsTranslator.to_parameter_pin(param, param.name&.to_s || parameter_names[arg_num] || "arg_#{arg_num}", :arg, closure, type_alias_decls: type_alias_decls)
        arg_num += 1
      end
      method_type.type.optional_positionals.each do |param|
        # @sg-ignore Unresolved call to name on RBS::Types::Function::Param
        params.push RbsTranslator.to_parameter_pin(param, param.name&.to_s || parameter_names[arg_num] || "arg_#{arg_num}", :optarg, closure, type_alias_decls: type_alias_decls)
        arg_num += 1
      end
      if method_type.type.rest_positionals
        # @sg-ignore Unresolved call to rest_positionals on generic<D>
        rest_positionals = method_type.type.rest_positionals
        # @sg-ignore Unresolved call to name on RBS::Types::Function::Param
        rest_name = rest_positionals.name&.to_s || parameter_names[arg_num] || "arg_#{arg_num}"
        params.push RbsTranslator.to_parameter_pin(rest_positionals, rest_name, :restarg, closure, type_alias_decls: type_alias_decls)
        arg_num += 1
      end
      method_type.type.required_keywords.each do |param|
        # @sg-ignore Unresolved calls to last, first on generic<D>
        params.push RbsTranslator.to_parameter_pin(param.last, param.first.to_s, :kwarg, closure, type_alias_decls: type_alias_decls)
        arg_num += 1
      end
      method_type.type.optional_keywords.each do |param|
        # @sg-ignore Unresolved calls to last, first on generic<D>
        params.push RbsTranslator.to_parameter_pin(param.last, param.first.to_s, :kwoptarg, closure, type_alias_decls: type_alias_decls)
        arg_num += 1
      end
      if method_type.type.rest_keywords
        # @sg-ignore Unresolved call to rest_keywords on generic<D>
        rest_keywords = method_type.type.rest_keywords
        # @sg-ignore Unresolved call to name on RBS::Types::Function::Param
        rest_keywords_name = rest_keywords.name&.to_s || parameter_names[arg_num] || "arg_#{arg_num}"
        params.push RbsTranslator.to_parameter_pin(rest_keywords, rest_keywords_name, :kwrestarg, closure, type_alias_decls: type_alias_decls)
      end
      params
    end

    # @param method_type [RBS::MethodType]
    # @param closure [Pin::Closure]
    # @param parameter_names [Array<String>]
    # @param type_alias_decls [Hash{String => RBS::AST::Declarations::TypeAlias}]
    # @return [Pin::Signature]
    def self.to_signature method_type, closure, parameter_names = [], type_alias_decls: {}
      # There may be edge cases here around different signatures
      # having different type params / orders - we may need to match
      # this data model and have generics live in signatures to
      # handle those correctly
      generics = method_type.type_params.map(&:name).map(&:to_s).uniq
      parameters = to_parameter_pins(method_type, closure, parameter_names, type_alias_decls: type_alias_decls)
      return_type = to_complex_type(method_type.type.return_type, type_alias_decls: type_alias_decls)
      block = if method_type.block
                block_parameters = to_parameter_pins(method_type.block, closure, type_alias_decls: type_alias_decls)
                block_return_type = to_complex_type(method_type.block.type.return_type, type_alias_decls: type_alias_decls)
                Pin::Signature.new(generics: generics, parameters: block_parameters, return_type: block_return_type, source: :rbs, type_location: closure.location, closure: closure)
              end
      Pin::Signature.new(generics: generics, parameters: parameters, return_type: return_type, block: block,
                         block_required: method_type.block&.required || false, source: :rbs, type_location: closure.location, closure: closure)
    end

    # Builds a named type (with its generic arguments, if any) directly
    # as an object rather than via a tag string, so `rooted?` survives.
    # https://github.com/castwide/solargraph/pull/870
    #
    # @param type_name [RBS::TypeName]
    # @param type_args [Enumerable<RBS::Types::Bases::Base>]
    # @param type_alias_decls [Hash{String => RBS::AST::Declarations::TypeAlias}]
    # @param expanding_aliases [Array<String>]
    # @return [ComplexType::UniqueType]
    def self.build_unique_type type_name, type_args = [], type_alias_decls: {}, expanding_aliases: []
      name = type_name.relative!.to_s
      base = RBS_TO_YARD_TYPE[name] || name
      params = type_args.map do |a|
        RbsTranslator.to_complex_type(a, type_alias_decls: type_alias_decls,
                                         expanding_aliases: expanding_aliases).force_rooted
      end
      if base == 'Hash' && params.length == 2
        ComplexType::UniqueType.new(base, [params.first], [params.last], rooted: true, parameters_type: :hash)
      else
        ComplexType::UniqueType.new(base, [], params.reject(&:undefined?), rooted: true, parameters_type: :list)
      end
    end

    # @param location [RBS::Location, nil]
    # @return [Solargraph::Location, nil]
    def self.to_sg_location(location)
      return nil if location.nil? || location.name.nil?

      start_pos = Position.new(location.start_line - 1, location.start_column)
      end_pos = Position.new(location.end_line - 1, location.end_column)
      range = Range.new(start_pos, end_pos)
      Location.new(location.name.to_s, range)
    end

    class << self
      private

      # @param type [RBS::Types::t]
      # @param type_alias_decls [Hash{String => RBS::AST::Declarations::TypeAlias}]
      # @param expanding_aliases [Array<String>]
      # @return [String]
      def type_to_tag type, type_alias_decls: {}, expanding_aliases: []
        # Every branch below narrows `type` by class via `when`, but
        # the type checker doesn't propagate that narrowing to calls
        # inside the branch body - it still sees the full RBS::Types::t
        # union, so calls to members that only exist on the matched
        # class (e.g. #type, #types, #literal, #name, #args) need an
        # inline ignore comment. Tracked at
        # https://github.com/castwide/solargraph/issues/1241
        case type
        when RBS::Types::Optional
          "#{type_to_tag(type.type, type_alias_decls: type_alias_decls, expanding_aliases: expanding_aliases)}, nil"
        when RBS::Types::Bases::Bool
          'Boolean'
        when RBS::Types::Tuple
          "Array(#{type.types.map { |t| type_to_tag(t, type_alias_decls: type_alias_decls, expanding_aliases: expanding_aliases) }.join(', ')})"
        when RBS::Types::Literal
          type.literal.inspect
        when RBS::Types::Union
          type.types.map { |t| type_to_tag(t, type_alias_decls: type_alias_decls, expanding_aliases: expanding_aliases) }.join(', ')
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
          # `&` binds tighter than `,`/`|`, so bracket a conjunct that
          # renders as more than one type (Union, Optional).
          #
          # @sg-ignore flow sensitive typing ought to be able to handle 'when ClassName'
          type.types.map { |member| intersection_conjunct_tag(member, type_alias_decls: type_alias_decls, expanding_aliases: expanding_aliases) }.join(' & ')
        when RBS::Types::Alias
          # A top-level type alias use, e.g. 'bool' in "type bool = true
          # | false". Expand to the alias's underlying type so structural
          # conformance checks can compare against its actual members
          # rather than its nominal name. Fall back to the nominal tag if
          # the alias definition isn't known, if it's recursive, or if
          # it's generic (e.g. "type box[T] = Array[T] | nil") -
          # expanding those would leak an unbound generic<T> tag, since
          # args aren't substituted into the expansion.
          alias_name = type.name.to_s
          alias_decl = type_alias_decls[alias_name]
          if alias_decl.nil? || expanding_aliases.include?(alias_name) || !type.args.empty?
            build_unique_type(type.name, type.args, type_alias_decls: type_alias_decls, expanding_aliases: expanding_aliases).tags
          else
            type_to_tag(alias_decl.type, type_alias_decls: type_alias_decls,
                        expanding_aliases: expanding_aliases + [alias_name])
          end
        when RBS::Types::ClassInstance, RBS::Types::Interface
          # `Interface` represents a mix-in module which can be considered a
          # subtype of a consumer of it
          #
          build_unique_type(type.name, type.args, type_alias_decls: type_alias_decls, expanding_aliases: expanding_aliases).tags
        when RBS::Types::ClassSingleton
          # e.g., singleton(String)
          build_unique_type(type.name, [], type_alias_decls: type_alias_decls, expanding_aliases: expanding_aliases).tags
        when RBS::Types::Proc
          'Proc'
        when RBS::Types::Bases::Any
          'undefined'
        when RBS::Types::Bases::Bottom
          # `Bottom` is used in contexts where nothing will ever return
          # - e.g., it could be the return type of 'exit()' or 'raise'
          'bot'
        else
          Solargraph.logger.warn "Unrecognized RBS type: #{type.class} at #{type.location}"
          'undefined'
        end
      end

      # @param member [RBS::Types::Bases::Base]
      # @param type_alias_decls [Hash{String => RBS::AST::Declarations::TypeAlias}]
      # @param expanding_aliases [Array<String>]
      # @return [String]
      def intersection_conjunct_tag member, type_alias_decls: {}, expanding_aliases: []
        tag = type_to_tag(member, type_alias_decls: type_alias_decls, expanding_aliases: expanding_aliases)
        member.is_a?(RBS::Types::Union) || member.is_a?(RBS::Types::Optional) ? "[#{tag}]" : tag
      end
    end
  end
end
