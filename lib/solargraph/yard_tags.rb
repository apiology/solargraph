# frozen_string_literal: true

require 'yard'

# Change YARD log IO to avoid sending unexpected messages to STDOUT
YARD::Logger.instance.io = File.new(File::NULL, 'w')

module Solargraph
  # A placeholder for the @!domain directive. It doesn't need to do anything
  # for yardocs. It's only used for Solargraph API maps.
  class DomainDirective < YARD::Tags::Directive
    def call; end
  end
end

# Define a @type tag for documenting variables
YARD::Tags::Library.define_tag('Type', :type, :with_types_and_name)

# Define a @pure tag for declaring that a method returns the same value for
# the same receiver and arguments, with no side effects
YARD::Tags::Library.define_tag('Pure', :pure)

# Define an @!override directive for overriding method tags
YARD::Tags::Library.define_directive('override', :with_name, Solargraph::DomainDirective)
