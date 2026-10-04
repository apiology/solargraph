# frozen_string_literal: true

module GemWithConcern
  # `class_methods` is ActiveSupport::Concern's way of declaring what a
  # including class gains. Plain YARD sees an unremarkable block; the
  # activesupport-concern plugin reads `greeting` out of it.
  module Greeting
    extend ActiveSupport::Concern

    class_methods do
      # @return [String]
      def greeting
        'hello'
      end
    end
  end
end
