# frozen_string_literal: true

require 'strscan'

module Solargraph
  module Parser
    # Finds the capture groups of a Regexp literal that take part in
    # every successful match: groups outside any quantifier that allows
    # zero repetitions and outside any alternation. Unsupported syntax
    # (interpolation, extended mode, named groups, lookarounds,
    # conditionals, subexpression calls) yields no groups.
    class RegexpGroups
      # @param node [::Parser::AST::Node] a :regexp node
      def initialize node
        @node = node
        # @type [::Array<Boolean>] indexed by group number - 1
        @required = []
      end

      # @return [::Array<Integer>] numbers of the groups that always match
      def required
        source = supported_source
        return [] if source.nil?

        @scanner = StringScanner.new(source)
        return [] if sequence.nil? || !@scanner.eos?

        @required.each_index.select { |index| @required[index] }.map(&:succ)
      end

      private

      # @return [String, nil]
      def supported_source
        return unless @node.children.length == 2

        str, opts = @node.children
        return unless str.type == :str && !opts.children.include?(:x)
        # %r literals unescape their delimiters, which could hide parens
        return unless @node.loc.begin.source == '/'

        str.children.first.to_s
      end

      # Scans up to an unmatched ')' or the end of the source.
      #
      # @return [::Array<Integer>, nil] numbers of the groups within, or
      #   nil if the syntax is unsupported
      def sequence
        members = []
        last = []
        alternation = false
        until @scanner.eos? || @scanner.check(/\)/)
          if @scanner.scan(/[?*]|\{0*,\d*\}|\{0+\}/)
            optional last
          elsif @scanner.scan(/\+|\{\d+,?\d*\}/)
            # repeats the last atom at least once
          elsif @scanner.scan('|')
            alternation = true
            last = []
          elsif @scanner.scan('(')
            last = group
            return if last.nil?

            members.concat last
          elsif @scanner.check(/\\g|\[/)
            return unless skip_class

            last = []
          else
            @scanner.scan(/\\./m) || @scanner.getch
            last = []
          end
        end
        optional members if alternation
        members
      end

      # Scans a group whose '(' was just consumed.
      #
      # @return [::Array<Integer>, nil]
      def group
        return [] if @scanner.scan(/\?[im-]*\)/)

        capture = nil
        unless @scanner.scan(/\?[im-]*:|\?>/)
          return if @scanner.check(/\?/)

          @required.push true
          capture = @required.length
        end
        inner = sequence
        return unless inner && @scanner.scan(')')

        inner + [capture].compact
      end

      # Scans a character class starting at '[', or rejects a '\g'
      # subexpression call.
      #
      # @return [Boolean] false if the syntax is unsupported
      def skip_class
        depth = 0
        until @scanner.eos? || @scanner.scan('\\g')
          if @scanner.scan('[')
            depth += 1
          elsif @scanner.scan(']')
            depth -= 1
          else
            @scanner.scan(/\\./m) || @scanner.getch
          end
          return true if depth.zero?
        end
        false
      end

      # @param numbers [::Array<Integer>]
      # @return [void]
      def optional numbers
        numbers.each { |number| @required[number - 1] = false }
      end
    end
  end
end
