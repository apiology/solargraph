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

    # Translates an RBS type into a ComplexType.
    #
    # Every RBS node that can *contain* another type - intersections,
    # unions, optionals, tuples, and generic type arguments - is built
    # directly as a ComplexType/UniqueType object graph by recursing
    # through this method, rather than by rendering a tag string and
    # re-parsing it. A joined string can't represent grouping that
    # Solargraph's own tag grammar has no syntax for (e.g. a union
    # nested inside an intersection, `(A | B) & C`), so round-tripping
    # through one silently produces the wrong structure. Only leaf
    # types that can't contain a nested type (literals, `bool`, `nil`,
    # `void`, generic type variables, `self`/`instance`, `Proc`, etc.)
    # go through the tag-string fallback in type_to_tag.
    #
    # @param type [RBS::Types::Bases::Base]
    # @param type_alias_decls [Hash{String => RBS::AST::Declarations::TypeAlias}]
    # @param expanding_aliases [Array<String>] Names of aliases already
    #   being expanded in this call chain, to detect recursive aliases
    # @return [ComplexType]
    def self.to_complex_type type, type_alias_decls: {}, expanding_aliases: []
      # See the comment on type_to_tag - case/when doesn't narrow
      # `type` for the type checker, so member calls that only exist
      # on the matched class (#name, #args) need an inline ignore
      # comment. Tracked at https://github.com/castwide/solargraph/issues/1241
      case type
      when RBS::Types::Intersection
        intersection_complex_type(type, type_alias_decls, expanding_aliases)
      when RBS::Types::Optional
        optional_complex_type(type, type_alias_decls, expanding_aliases)
      when RBS::Types::Union
        union_complex_type(type, type_alias_decls, expanding_aliases)
      when RBS::Types::Tuple
        tuple_complex_type(type, type_alias_decls, expanding_aliases)
      when RBS::Types::Alias
        # A top-level type alias use, e.g., 'bool' in "type bool = true
        # | false". Expand to the alias's underlying type so structural
        # conformance checks (e.g., typechecking) can compare against
        # its actual members rather than its nominal name. Fall back to
        # the nominal tag if the alias definition isn't known, if it's
        # recursive, or if it's generic (e.g. "type box[T] = Array[T] |
        # nil") - expanding those would leak an unbound generic<T> tag,
        # since args aren't substituted into the expansion.
        # @sg-ignore https://github.com/castwide/solargraph/issues/1241 - case/when doesn't narrow type
        alias_name = type.name.to_s
        alias_decl = type_alias_decls[alias_name]
        # @sg-ignore https://github.com/castwide/solargraph/issues/1241 - case/when doesn't narrow type
        if alias_decl.nil? || expanding_aliases.include?(alias_name) || !type.args.empty?
          # @sg-ignore https://github.com/castwide/solargraph/issues/1241 - case/when doesn't narrow type
          ComplexType.new([build_unique_type(type.name, type.args, type_alias_decls: type_alias_decls, expanding_aliases: expanding_aliases)]).force_rooted
        else
          # @sg-ignore Wrong argument type for to_complex_type: type expected RBS::Types::Bases::Base, received union of concrete subtypes
          to_complex_type(alias_decl.type, type_alias_decls: type_alias_decls, expanding_aliases: expanding_aliases + [alias_name])
        end
      when RBS::Types::ClassInstance, RBS::Types::Interface
        # `Interface` represents a mix-in module which can be considered a
        # subtype of a consumer of it
        # @sg-ignore https://github.com/castwide/solargraph/issues/1241 - case/when doesn't narrow type
        ComplexType.new([build_unique_type(type.name, type.args, type_alias_decls: type_alias_decls, expanding_aliases: expanding_aliases)]).force_rooted
      when RBS::Types::ClassSingleton
        # e.g., singleton(String)
        # @sg-ignore https://github.com/castwide/solargraph/issues/1241 - case/when doesn't narrow type
        ComplexType.new([build_unique_type(type.name, type_alias_decls: type_alias_decls, expanding_aliases: expanding_aliases)]).force_rooted
      else
        tag = type_to_tag(type)
        ComplexType.try_parse(tag).force_rooted
      end
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
                      # @sg-ignore Wrong argument type for to_complex_type: type expected RBS::Types::Bases::Base, received union of concrete subtypes
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
      # @sg-ignore Wrong argument type for to_complex_type: type expected RBS::Types::Bases::Base, received union of concrete subtypes
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
      # @sg-ignore Wrong argument type for to_complex_type: type expected RBS::Types::Bases::Base, received union of concrete subtypes
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
      # @sg-ignore Wrong argument type for to_complex_type: type expected RBS::Types::Bases::Base, received union of concrete subtypes
      return_type = to_complex_type(method_type.type.return_type, type_alias_decls: type_alias_decls)
      block = if method_type.block
                block_parameters = to_parameter_pins(method_type.block, closure, type_alias_decls: type_alias_decls)
                # @sg-ignore Wrong argument type for to_complex_type: type expected RBS::Types::Bases::Base, received union of concrete subtypes
                block_return_type = to_complex_type(method_type.block.type.return_type, type_alias_decls: type_alias_decls)
                Pin::Signature.new(generics: generics, parameters: block_parameters, return_type: block_return_type, source: :rbs, type_location: closure.location, closure: closure)
              end
      Pin::Signature.new(generics: generics, parameters: parameters, return_type: return_type, block: block,
                         block_required: method_type.block&.required || false, source: :rbs, type_location: closure.location, closure: closure)
    end

    # @param type_name [RBS::TypeName]
    # @param type_args [Enumerable<RBS::Types::Bases::Base>]
    # @param type_alias_decls [Hash{String => RBS::AST::Declarations::TypeAlias}]
    # @param expanding_aliases [Array<String>]
    # @return [ComplexType::UniqueType]
    def self.build_unique_type type_name, type_args = [], type_alias_decls: {}, expanding_aliases: []
      base = RBS_TO_YARD_TYPE[type_name.relative!.to_s] || type_name.relative!.to_s
      params = type_args.map do |a|
        RbsTranslator.to_complex_type(a, type_alias_decls: type_alias_decls, expanding_aliases: expanding_aliases)
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

      # @param type [RBS::Types::Intersection]
      # @param type_alias_decls [Hash{String => RBS::AST::Declarations::TypeAlias}]
      # @param expanding_aliases [Array<String>]
      # @return [ComplexType]
      def intersection_complex_type type, type_alias_decls = {}, expanding_aliases = []
        # @sg-ignore Wrong argument type for to_complex_type: type expected RBS::Types::Bases::Base, received union of concrete subtypes
        conjuncts = type.types.map { |member| RbsTranslator.to_complex_type(member, type_alias_decls: type_alias_decls, expanding_aliases: expanding_aliases) }
        ComplexType.new([ComplexType::UniqueType::Intersection.new(conjuncts)]).force_rooted
      end

      # @param type [RBS::Types::Optional]
      # @param type_alias_decls [Hash{String => RBS::AST::Declarations::TypeAlias}]
      # @param expanding_aliases [Array<String>]
      # @return [ComplexType]
      def optional_complex_type type, type_alias_decls = {}, expanding_aliases = []
        # @sg-ignore Wrong argument type for to_complex_type: type expected RBS::Types::Bases::Base, received union of concrete subtypes
        inner = RbsTranslator.to_complex_type(type.type, type_alias_decls: type_alias_decls, expanding_aliases: expanding_aliases)
        ComplexType.new(inner.items + [ComplexType::UniqueType::NIL]).force_rooted
      end

      # @param type [RBS::Types::Union]
      # @param type_alias_decls [Hash{String => RBS::AST::Declarations::TypeAlias}]
      # @param expanding_aliases [Array<String>]
      # @return [ComplexType]
      def union_complex_type type, type_alias_decls = {}, expanding_aliases = []
        # @sg-ignore Wrong argument type for to_complex_type: type expected RBS::Types::Bases::Base, received union of concrete subtypes
        ComplexType.new(type.types.flat_map { |t| RbsTranslator.to_complex_type(t, type_alias_decls: type_alias_decls, expanding_aliases: expanding_aliases).items }).force_rooted
      end

      # @param type [RBS::Types::Tuple]
      # @param type_alias_decls [Hash{String => RBS::AST::Declarations::TypeAlias}]
      # @param expanding_aliases [Array<String>]
      # @return [ComplexType]
      def tuple_complex_type type, type_alias_decls = {}, expanding_aliases = []
        # @sg-ignore Wrong argument type for to_complex_type: type expected RBS::Types::Bases::Base, received union of concrete subtypes
        subtypes = type.types.map { |t| RbsTranslator.to_complex_type(t, type_alias_decls: type_alias_decls, expanding_aliases: expanding_aliases) }
        ComplexType.new([ComplexType::UniqueType.new('Array', [], subtypes, rooted: true, parameters_type: :fixed)]).force_rooted
      end

      # Renders a leaf RBS type (one that can't contain another type)
      # as a tag string. Composite/recursive types (Optional, Union,
      # Tuple, Intersection, Alias, ClassInstance, ClassSingleton) are
      # handled directly in to_complex_type instead - see its comment.
      #
      # @param type [RBS::Types::Bases::Base]
      # @return [String]
      def type_to_tag type
        # Every branch below narrows `type` by class via `when`, but
        # the type checker doesn't propagate that narrowing to calls
        # inside the branch body - it still sees the full RBS::Types::t
        # union, so calls to members that only exist on the matched
        # class (e.g. #type, #types, #literal, #name, #args) need an
        # inline ignore comment. Tracked at
        # https://github.com/castwide/solargraph/issues/1241
        case type
        when RBS::Types::Bases::Bool
          'Boolean'
        when RBS::Types::Literal
          # @sg-ignore https://github.com/castwide/solargraph/issues/1241 - case/when doesn't narrow type
          type.literal.inspect
        when RBS::Types::Record
          # @todo Better record support
          'Hash'
        when RBS::Types::Bases::Nil
          'nil'
        when RBS::Types::Bases::Void
          'void'
        when RBS::Types::Variable
          # @sg-ignore https://github.com/castwide/solargraph/issues/1241 - case/when doesn't narrow type
          "#{Solargraph::ComplexType::GENERIC_TAG_NAME}<#{type.name}>"
        when RBS::Types::Bases::Self, RBS::Types::Bases::Instance
          'self'
        when RBS::Types::Bases::Top
          # `Top` is the most super superclass
          'BasicObject'
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
    end
  end
end
