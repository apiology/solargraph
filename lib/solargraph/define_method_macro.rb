# frozen_string_literal: true

module Solargraph
  # A method that calls define_method or define_singleton_method with a name
  # taken from one of its own parameters, e.g., ActionController's
  #
  #   def add_flash_types(*types)
  #     types.each { |type| define_method(type) { request.flash[type] } }
  #   end
  #
  # A call to the method with literal names, e.g., +add_flash_types :alert+,
  # generates the methods it defines.
  #
  # Only the method's own parameters are followed, either directly or through
  # +param.each { |name| ... }+, and only Symbol and String literals in the
  # call's arguments produce names.
  class DefineMethodMacro
    # The methods that define a method and the scope of the methods they
    # define when called at class level.
    DEFINERS = { define_method: :instance, define_singleton_method: :class }.freeze

    # Parameter node types and their Pin::Parameter declarations
    PARAMETER_DECLS = {
      arg: :arg, optarg: :optarg, restarg: :restarg, kwarg: :kwarg,
      kwoptarg: :kwoptarg, kwrestarg: :kwrestarg, blockarg: :blockarg
    }.freeze

    # The parameters given to a defined method whose body is not a literal
    # block, e.g., +define_method(name, &block)+
    UNKNOWN_PARAMETERS = [[:restarg, 'args'], [:kwrestarg, 'kwargs'], [:blockarg, 'block']].freeze

    # @return [Integer] the position of the argument that supplies names
    attr_reader :position

    # @return [::Symbol] :name if the argument is a name, :splat if every
    #   argument from the position onward is a name, :array if the argument
    #   is an array of names
    attr_reader :mode

    # @return [::Symbol] :instance or :class
    attr_reader :scope

    # @return [::Array<::Array(::Symbol, String)>] the declarations and names
    #   of the defined method's parameters
    attr_reader :parameters

    # @param position [Integer]
    # @param mode [::Symbol]
    # @param scope [::Symbol]
    # @param parameters [::Array<::Array(::Symbol, String)>]
    def initialize position:, mode:, scope:, parameters:
      @position = position
      @mode = mode
      @scope = scope
      @parameters = parameters
    end

    # @param other [Object]
    def == other
      other.is_a?(DefineMethodMacro) && to_a == other.to_a
    end

    # @return [::Array(Integer, ::Symbol, ::Symbol, ::Array<::Array(::Symbol, String)>)]
    def to_a
      [position, mode, scope, parameters]
    end

    # The methods a call to the macro generates.
    #
    # @param call [::Parser::AST::Node] the send node that calls the macro
    # @param closure [Pin::Namespace] the namespace the call is made in
    # @param location [Location] the call's location
    # @return [::Array<Pin::Method>]
    def generate_pins call, closure, location
      names_from(call).map do |name|
        pin = Pin::Method.new(location: location, closure: closure, name: name, scope: scope,
                              visibility: :public, source: :parser)
        parameters.each do |decl, param_name|
          pin.parameters.push Pin::Parameter.new(name: param_name, decl: decl, closure: pin, source: :parser)
        end
        pin
      end
    end

    class << self
      # @param node [::Parser::AST::Node, nil] a def or defs node
      # @return [::Array<DefineMethodMacro>]
      def from_def_node node
        return [] if node.nil?
        return [] unless %i[def defs].include?(node.type)
        args, body = node.type == :def ? node.children.drop(1) : node.children.drop(2)
        positions = positional_parameters(args)
        return [] if positions.empty?
        # @type [::Array<DefineMethodMacro>]
        result = []
        collect body, positions, {}, result
        result
      end

      private

      # The method's positional parameters up to and including a rest
      # parameter, which maps every argument after it.
      #
      # @param args [::Parser::AST::Node]
      # @return [Hash{::Symbol => ::Array(Integer, ::Symbol)}] name => [position, type]
      def positional_parameters args
        # @type [Hash{::Symbol => ::Array(Integer, ::Symbol)}]
        result = {}
        return result unless Parser.is_ast_node?(args)
        args.children.each_with_index do |arg, index|
          break unless %i[arg optarg restarg].include?(arg.type)
          result[arg.children.first.to_s.to_sym] = [index, arg.type]
          break if arg.type == :restarg
        end
        result
      end

      # Children of AST nodes are typed as nodes, but leaves can be other
      # values, so each node parameter below is checked with is_ast_node?.
      #
      # @param node [::Parser::AST::Node]
      # @param positions [Hash{::Symbol => ::Array(Integer, ::Symbol)}]
      # @param each_vars [Hash{::Symbol => ::Symbol}] block variable => the
      #   parameter whose elements it iterates
      # @param result [::Array<DefineMethodMacro>]
      # @return [void]
      def collect node, positions, each_vars, result
        return unless Parser.is_ast_node?(node)
        return if %i[def defs class module sclass].include?(node.type)
        call, block_args, block_body = node.children
        if node.type == :block && definer?(call)
          add_macro call, block_args, positions, each_vars, result
          collect block_body, positions, each_vars, result
          return
        end
        add_macro node, nil, positions, each_vars, result if definer?(node)
        each_vars = each_vars.merge(each_variable(node, positions)) if node.type == :block
        node.children.each { |child| collect child, positions, each_vars, result }
      end

      # @param node [::Parser::AST::Node]
      # @return [Boolean]
      def definer? node
        return false unless Parser.is_ast_node?(node) && node.type == :send
        receiver, method_name = node.children
        return false unless DEFINERS.key?(method_name.to_s.to_sym)
        receiver.nil? || (Parser.is_ast_node?(receiver) && receiver.type == :self)
      end

      # The block variable of +param.each { |var| ... }+, mapped to +param+.
      #
      # @param node [::Parser::AST::Node] a block node
      # @param positions [Hash{::Symbol => ::Array(Integer, ::Symbol)}]
      # @return [Hash{::Symbol => ::Symbol}]
      def each_variable node, positions
        call, args = node.children
        receiver, method_name = call.children
        return {} unless call.type == :send && method_name.to_s == 'each' && call.children.length == 2
        return {} unless Parser.is_ast_node?(receiver) && receiver.type == :lvar
        param = receiver.children.first.to_s.to_sym
        return {} unless positions.key?(param) && args.children.length == 1
        var = block_variable(args.children.first)
        var ? { var => param } : {}
      end

      # @param arg [::Parser::AST::Node, nil]
      # @return [::Symbol, nil]
      def block_variable arg
        return nil if arg.nil?
        return arg.children.first.to_s.to_sym if arg.type == :arg
        return nil unless arg.type == :procarg0 && arg.children.length == 1
        inner = arg.children.first
        return block_variable(inner) if Parser.is_ast_node?(inner)
        inner.to_s.to_sym
      end

      # @param send [::Parser::AST::Node] the define_method call
      # @param block_args [::Parser::AST::Node, nil] the defined method's
      #   parameters, if its body is a literal block
      # @param positions [Hash{::Symbol => ::Array(Integer, ::Symbol)}]
      # @param each_vars [Hash{::Symbol => ::Symbol}]
      # @param result [::Array<DefineMethodMacro>]
      # @return [void]
      def add_macro send, block_args, positions, each_vars, result
        _receiver, method_name, name = send.children
        return unless Parser.is_ast_node?(name) && name.type == :lvar
        var = name.children.first.to_s.to_sym
        iterated = each_vars[var]
        param = positions[iterated || var]
        return if param.nil?
        position, type = param
        if iterated
          mode = type == :restarg ? :splat : :array
        else
          return if type == :restarg
          mode = :name
        end
        result.push new(position: position, mode: mode, scope: DEFINERS.fetch(method_name.to_s.to_sym),
                        parameters: block_parameters(block_args))
      end

      # @param args [::Parser::AST::Node, nil]
      # @return [::Array<::Array(::Symbol, String)>]
      def block_parameters args
        return UNKNOWN_PARAMETERS if args.nil?
        args.children.filter_map do |arg|
          variable = block_variable(arg)
          next [:arg, variable.to_s] if arg.type == :procarg0 && variable
          decl = PARAMETER_DECLS[arg.type]
          [decl, arg.children.first.to_s] if decl
        end
      end
    end

    private

    # @param call [::Parser::AST::Node]
    # @return [::Array<String>]
    def names_from call
      args = call.children.drop(2).reject { |arg| arg.type == :block_pass }
      # A trailing hash is keyword arguments, not a name
      args.pop if args.last&.type == :hash
      # Splatted arguments make the positions unknowable
      return [] if args.take(position + 1).any? { |arg| arg.type == :splat }
      case mode
      when :name
        [literal_name(args[position])].compact
      when :splat
        args.drop(position).take_while { |arg| arg.type != :splat }.filter_map { |arg| literal_name(arg) }
      else
        array = args[position]
        return [] if array.nil? || array.type != :array
        array.children.filter_map { |arg| literal_name(arg) }
      end
    end

    # @param node [::Parser::AST::Node, nil]
    # @return [String, nil]
    def literal_name node
      return nil if node.nil?
      return nil unless %i[sym str].include?(node.type)
      name = node.children.first.to_s
      name.empty? ? nil : name
    end
  end
end
