# frozen_string_literal: true

require 'prism'

module Solargraph
  module Parser
    module ParserGem
      module ClassMethods
        # @param code [String]
        # @param filename [String, nil]
        # @param starting_line [Integer] must be provided so that we
        #   can find relevant local variables later even if this is just
        #   a subset of the file in question
        # @return [Array(Parser::AST::Node, Hash{Integer => Solargraph::Parser::Snippet}),
        #   Array(nil, Hash{Integer => Solargraph::Parser::Snippet})]
        def parse_with_comments code, filename = nil, starting_line = 0
          node = parse(code, filename, starting_line)
          comments = CommentRipper.new(code, filename, 0).parse
          [node, comments]
        end

        # @param code [String]
        # @param filename [String, nil]
        # @param starting_line [Integer]
        # @return [Parser::AST::Node, nil] nil when the code has no expressions
        def parse code, filename = nil, starting_line = 0
          buffer = ::Parser::Source::Buffer.new(filename, starting_line)
          buffer.source = code
          parser.parse(buffer)
        rescue ::Parser::SyntaxError, ::Parser::UnknownEncodingInMagicComment => e
          raise Parser::SyntaxError, e.message
        end

        # A new parser per call: Prism::Translation::Parser keeps the buffer
        # it is parsing in an instance variable, so one shared instance
        # fails when several threads parse at once.
        #
        # @return [::Parser::Base]
        def parser
          Prism::Translation::Parser.new(FlawedBuilder.new).tap do |parser|
            parser.diagnostics.all_errors_are_fatal = true
            parser.diagnostics.ignore_warnings      = true
          end
        end

        # @param source [Source]
        # @return [Array(Array<Pin::Base>, Array<Pin::LocalVariable>)]
        def map source
          pins, locals, ivars = NodeProcessor.process(source.node, Region.new(source: source))
          pins.concat(ivars)
          [pins, locals]
        end

        # @param source [Source]
        # @param name [String]
        # @return [Array<Location>]
        def references source, name
          if name.end_with?('=')
            reg = /#{Regexp.escape name.chomp('=')}\s*=/
            # @param code [String]
            # @param offset [Integer]
            # @return [Array(Integer, Integer), Array(nil, nil)]
            extract_offset = lambda do |code, offset|
              match = reg.match(code, offset)
              match ? match.offset(0) : [nil, nil]
            end
          else
            # @param code [String]
            # @param offset [Integer]
            # @return [Array(Integer, Integer), Array(nil, nil)]
            extract_offset = lambda do |code, offset|
              soff = code.index(name, offset)
              soff ? [soff, soff + name.length] : [nil, nil]
            end
          end
          inner_node_references(name, source.node).filter_map do |n|
            rng = Range.from_node!(n)
            offset = Position.to_offset(source.code, rng.start)
            soff, eoff = extract_offset[source.code, offset]
            # Operator calls like foo[0] do not spell the method name
            next unless soff && eoff

            Location.new(
              source.filename,
              Range.new(
                Position.from_offset(source.code, soff),
                Position.from_offset(source.code, eoff)
              )
            )
          end
        end

        # @param name [String]
        # @param top [AST::Node, Object, nil]
        # @return [Array<AST::Node>]
        def inner_node_references name, top
          # @type [Array<AST::Node>]
          result = []
          if top.is_a?(AST::Node) && top.to_s.include?(":#{name}")
            result.push top if top.children.any? { |c| c.to_s == name }
            top.children.each { |c| result.concat inner_node_references(name, c) }
          end
          result
        end

        # @return [Source::Chain]
        def chain *args
          NodeChainer.chain(*args)
        end

        # @return [Source::Chain]
        def chain_string *args
          NodeChainer.load_string(*args)
        end

        # @return [Array(Array<Pin::Base>, Array<Pin::Base>)]
        def process_node *args
          Solargraph::Parser::NodeProcessor.process(*args)
        end

        # @param node [Parser::AST::Node, nil]
        # @return [String, nil]
        def infer_literal_node_type node
          NodeMethods.infer_literal_node_type node
        end

        # @return [Integer]
        def version
          parser.version
        end

        # @param node [Parser::AST::Node]
        # @return [Range]
        def node_range node
          st = Position.new(node.loc.line, node.loc.column)
          en = Position.new(node.loc.last_line, node.loc.last_column)
          Range.new(st, en)
        end

        # @param node [Parser::AST::Node, nil]
        # @return [Array<Range>]
        def string_ranges node
          return [] unless node.is_a?(::Parser::AST::Node)
          result = []
          result.push Range.from_node(node) if node.type == :str
          node.children.each do |child|
            # @sg-ignore https://github.com/castwide/solargraph/pull/1416
            result.concat string_ranges(child)
          end
          if node.type == :dstr && node.children.last.nil?
            # :nocov:
            # Dead under the parser gem: it never emits a dstr whose last child is
            # a literal nil, so last is only ever nil here and no range is pushed.
            # The shape comes from RubyVM::AbstractSyntaxTree, whose DSTR nodes do
            # carry a trailing nil child.
            last = node.children[-2]
            unless last.nil?
              # @sg-ignore https://github.com/castwide/solargraph/pull/1416
              rng = Range.from_node!(last)
              pos = Position.new(rng.ending.line, rng.ending.column - 1)
              result.push Range.new(pos, pos)
            end
            # :nocov:
          end
          result
        end
      end
    end
  end
end
