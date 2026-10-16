# frozen_string_literal: true

module Solargraph
  class Source
    class Chain
      # MatchData#[] declares its result nilable, but some groups take
      # part in every successful match: group 0, and the required
      # groups of a Regexp literal passed to String#match.
      module MatchGroup
        # @param link [Link, nil] the link just resolved
        # @param pins [::Array<Pin::Base>] what link resolved to
        # @param receiver_link [Link, nil] the link before link
        # @param receiver_pins [::Array<Pin::Base>] what receiver_link resolved to
        # @param api_map [ApiMap]
        # @return [::Array<Pin::Base>]
        def self.narrow link, pins, receiver_link, receiver_pins, api_map
          return pins unless link.is_a?(Chain::Call) && link.word == '[]' && pins.any? { |pin| pin.path == 'MatchData#[]' }

          number = group_number(link)
          return pins unless number&.zero? || regexps(receiver_link, receiver_pins, api_map)&.all? do |regexp|
            Parser::RegexpGroups.new(regexp).required.include?(number)
          end

          pins.map do |pin|
            pin.path == 'MatchData#[]' ? pin.proxy(pin.return_type.without_nil) : pin
          end
        end

        # @param link [Chain::Call]
        # @return [Integer, nil] the literal Integer argument, if any
        def self.group_number link
          return unless link.arguments.length == 1

          int_value link.arguments.fetch(0).node
        end

        # @param node [::Parser::AST::Node, nil]
        # @return [Integer, nil] node's value, if it is an Integer literal
        def self.int_value node
          return unless node && node.type == :int

          number = node.children.first
          number if number.is_a?(Integer)
        end

        # @param receiver_link [Link, nil]
        # @param receiver_pins [::Array<Pin::Base>]
        # @param api_map [ApiMap]
        # @return [::Array<::Parser::AST::Node>, nil] the :regexp nodes
        #   the receiver could have been matched against
        def self.regexps receiver_link, receiver_pins, api_map
          nodes = if string_match?(receiver_pins) && receiver_link.is_a?(Chain::Call) &&
                     receiver_link.arguments.length == 1 && !receiver_link.with_block?
                    [regexp_node(receiver_link.arguments.fetch(0).node)]
                  elsif !receiver_pins.empty? && receiver_pins.all? { |pin| pin.instance_of?(Pin::LocalVariable) }
                    # @param pin [Pin::LocalVariable]
                    receiver_pins.flat_map { |pin| pin.assignments.map { |node| assigned_regexp(node, pin, api_map) } }
                  else
                    []
                  end
          nodes.compact if !nodes.empty? && nodes.all?
        end

        # @param node [::Parser::AST::Node] the value assigned to pin
        # @param pin [Pin::LocalVariable]
        # @param api_map [ApiMap]
        # @return [::Parser::AST::Node, nil]
        def self.assigned_regexp node, pin, api_map
          location = pin.location
          closure = pin.closure
          return unless location && closure && %i[send csend].include?(node.type)

          locals = api_map.source_map(location.filename).locals_at(location)
          chain = Parser.chain(node, location.filename)
          regexp_node(node.children[2]) if string_match?(chain.define(api_map, closure, locals))
        end

        # @param node [::Parser::AST::Node, nil]
        # @return [::Parser::AST::Node, nil] node, if it is a Regexp literal
        def self.regexp_node node
          node if node&.type == :regexp
        end

        # @param pins [::Array<Pin::Base>]
        # @return [Boolean] whether every pin is String#match
        def self.string_match? pins
          !pins.empty? && pins.all? { |pin| pin.path == 'String#match' }
        end
      end
    end
  end
end
