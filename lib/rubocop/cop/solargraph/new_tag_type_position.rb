# frozen_string_literal: true

require 'yard'
require 'rubocop-yard'

module ::RuboCop
  module Cop
    module Solargraph
      class NewTagTypePosition < ::RuboCop::Cop::Base
        include RuboCop::Cop::YARD::Helper
        include RangeHelp

        def on_new_investigation
          # file_path = processed_source.file_path

          # @todo This does not resolve correctly automatically
          # @type [RuboCop::AST::ProcessedSource]
          src = processed_source

          # @todo this should be an intersection type, not a union type - no YARD syntax yet
          # @param comment [RuboCop::AST::Node, Parser::Source::Comment]
          src.comments.each do |comment|
            # @sg-ignore this should be an intersection type, not a union type - no YARD syntax yet
            next if inline_comment?(comment)
            # @sg-ignore this should be an intersection type, not a union type - no YARD syntax yet
            next unless include_yard_tag?(comment)
            # @sg-ignore this should be an intersection type, not a union type - no YARD syntax yet
            next unless include_yard_tag_type?(comment)

            # @sg-ignore this should be an intersection type, not a union type - no YARD syntax yet
            check(comment)
          end
        end

        private

        # @todo Changing this to ::Parser::Source::Comemnt
        #   results in Missing @param tag for comment on
        #   RuboCop::Cop::Solargraph::NewTagTypePosition#check
        #
        # @param comment [::Parser::Source::Comment]
        #
        # @return [void]
        def check(comment)
          # uncomment this to see this cop report
          # add_offense(comment, message: "I hate comments")

          docstring = comment.text.gsub(/\A#\s*/, '')
          ::YARD::DocstringParser.new.parse(docstring).tags.each do |tag|
            types = extract_tag_types(tag)
            next unless types.nil?

            # @sg-ignore this should be an intersection type, not a union type - no YARD syntax yet
            # @type [MatchData, nil]
            match = comment.source.match(/(?<type>\[.+\])/)
            next if match.nil?
            add_offense(comment, message: "This docs found `#{match[:type]}`, but parser of YARD can't found types. Please check syntax of YARD.")
          end
        end

        # @param comment [::RuboCop::AST::Node]
        #
        # @return [void]
        def include_yard_tag?(comment)
          comment.source.match?(/@(?:param|return|option|raise|yieldparam|yieldreturn)\s+.*\[.*\]/)
        end

        # @sg-ignore Missing @param tag for comment on RuboCop::Cop::Solargraph::NewTagTypePosition#check
        #
        # @param comment [::RuboCop::AST::Node]
        def include_yard_tag_type?(comment)
          comment.source.match?(/\[.+\]/)
        end
      end
    end
  end
end
