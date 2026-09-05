# frozen_string_literal: true

module Solargraph
  class Source
    class Chain
      class Hash < Literal
        # @param type [String]
        # @param node [Parser::AST::Node]
        # @param splatted [Boolean]
        # @param pairs [::Array<::Array(Chain, Chain)>, nil] Each key/value
        #   pair's key and value chained separately, or nil if the literal
        #   isn't just a plain list of `key => value` pairs (e.g. it
        #   contains a `**splat`) - see NodeChainer#hash_pairs.
        def initialize type, node, splatted = false, pairs = nil
          super(type, node)
          @splatted = splatted
          # @type [::Array<::Array(Chain, Chain)>, nil]
          @pairs = pairs
        end

        def word
          @word ||= "<#{@type}>"
        end

        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base]
        # @param locals [::Array<Pin::Base>]
        # @param _receiver_path [::Array<String>, nil]
        def resolve api_map, name_pin, locals, _receiver_path = nil
          [Pin::ProxyType.anonymous(inferred_type(api_map, name_pin, locals), source: :chain)]
        end

        def splatted?
          @splatted
        end

        # Infers a per-key "record" type from the literal's actual pairs:
        # an intersection of single-key Hash{K => V} conjuncts, one per
        # pair, keeping each key's own literal type rather than merging
        # every pair into one aggregate Hash{K => V} the way
        # #inferred_type does. That per-key pairing is what lets a
        # declared record-type expectation (Hash{:k1 => V1} & Hash{:k2 =>
        # V2} & ...) check "does the literal have this key, and if so
        # does its value conform" - the aggregate type has already lost
        # which value went with which key by the time it's checked.
        #
        # Returns nil under the same conditions #inferred_type falls back
        # for (splatted hash, or a pair whose key or value fails to
        # infer).
        #
        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base]
        # @param locals [::Array<Pin::Base>]
        # @return [ComplexType, nil]
        def record_type api_map, name_pin, locals
          pairs = @pairs
          return nil if pairs.nil? || pairs.empty?

          conjuncts = pairs.map do |pair|
            key_chain, value_chain = pair
            key_type = key_chain.infer(api_map, name_pin, locals)
            value_type = value_chain.infer(api_map, name_pin, locals).simplify_literals
            return nil if key_type.undefined? || value_type.undefined?

            ComplexType.new([ComplexType::UniqueType.new('Hash', [key_type], [value_type],
                                                         rooted: true, parameters_type: :hash)])
          end
          ComplexType.new([ComplexType::UniqueType::Intersection.new(conjuncts)])
        end

        protected

        def equality_fields
          super + [@splatted]
        end

        private

        # Infers Hash{K => V} from the literal's actual key/value pairs,
        # the same way Chain::Array infers Array<T> from its elements
        # (see Chain::Array#resolve). Falls back to the bare, generic-less
        # ::Hash type - the only type a splatted hash or one that fails to
        # infer any pair concretely ever had - rather than reporting a
        # partial/incorrect Hash{K => V}.
        #
        # @param api_map [ApiMap]
        # @param name_pin [Pin::Base]
        # @param locals [::Array<Pin::Base>]
        # @return [ComplexType]
        def inferred_type api_map, name_pin, locals
          # @type [::Array<::Array(Chain, Chain)>, nil]
          pairs = @pairs
          return @complex_type if pairs.nil? || pairs.empty?

          key_types = []
          value_types = []
          pairs.each do |pair|
            key_chain, value_chain = pair
            key_type = key_chain.infer(api_map, name_pin, locals).simplify_literals
            value_type = value_chain.infer(api_map, name_pin, locals).simplify_literals
            return @complex_type if key_type.undefined? || value_type.undefined?

            key_types.push key_type
            value_types.push value_type
          end
          ComplexType.new([ComplexType::UniqueType.new('Hash', key_types.uniq, value_types.uniq,
                                                       rooted: true, parameters_type: :hash)])
        end
      end
    end
  end
end
