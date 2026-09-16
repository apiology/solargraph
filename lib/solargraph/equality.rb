# frozen_string_literal: true

module Solargraph
  # @abstract This mixin relies on these -
  #   methods:
  #     equality_fields()
  module Equality
    # @!method equality_fields
    #   @return [Array]

    # @param other [Object]
    # @return [Boolean]
    def eql? other
      self.class.eql?(other.class) &&
        # @sg-ignore flow sensitive typing should support .class == .class
        equality_fields.eql?(other.equality_fields)
    end

    # @param other [Object]
    # @return [Boolean]
    def == other
      eql?(other)
    end

    def hash
      equality_fields.hash
    end

    # A Module in equality_fields discriminates #hash rather than holding
    # state; freezing it would block definition and autoload under it.
    def freeze
      equality_fields.grep_v(Module).each(&:freeze)
      super
    end
  end
end
