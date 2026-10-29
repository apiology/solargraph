# frozen_string_literal: true

module Solargraph
  class ComplexType
    class UniqueType
      # A single unique type for an RBS record, e.g.
      # `{ name: String, ?port: Integer }`: a Hash with a fixed set of
      # literal keys, each typed on its own.
      #
      # It reads and conforms as the Hash it describes, here
      # `Hash{Symbol => String, Integer}`, which is also how it renders
      # as a tag, since YARD has no record syntax. Reading a field with a
      # literal key (`record[:port]`) gets that field's own type, nil
      # included when the field is optional, and #to_rbs prints the
      # record back as written.
      #
      # @see https://github.com/ruby/rbs/blob/master/docs/syntax.md#record-type
      # @sg-ignore https://github.com/castwide/solargraph/pull/1244
      class Record < Solargraph::Type
        include Equality

        # @return [Hash{::Symbol, ::String => ComplexType}] each field's type, in declaration order
        attr_reader :fields

        # @return [Array<::Symbol, ::String>] the keys a record may leave out
        attr_reader :optional_keys

        # @param fields [Hash{::Symbol, ::String => ComplexType}] each field's type, in declaration order
        # @param optional_keys [Array<::Symbol, ::String>] the keys a record may leave out
        # @return [void]
        def initialize fields, optional_keys = []
          # @sg-ignore https://github.com/castwide/solargraph/pull/1244
          super()
          @fields = fields
          @optional_keys = optional_keys
        end

        # @param key [::Symbol, ::String]
        # @return [Boolean]
        def optional? key
          optional_keys.include?(key)
        end

        # The Hash this record describes: its key classes to the union
        # of its field types. Optional fields join the union without
        # nil, as with any key missing from a Hash.
        #
        # @return [UniqueType]
        def hash_type
          @hash_type ||= UniqueType.new('Hash',
                                        fields.keys.map { |key| ComplexType.parse("::#{key.class}") }
                                              .uniq(&:rooted_tags),
                                        fields.values.uniq(&:rooted_tags),
                                        rooted: true, parameters_type: :hash)
        end

        # @return [String]
        def tag
          hash_type.tag
        end

        # @return [String]
        def tags
          hash_type.tags
        end

        # @return [String]
        def rooted_tag
          hash_type.rooted_tag
        end

        # @return [String]
        def rooted_tags
          hash_type.rooted_tags
        end

        # @return [String]
        def to_s
          tags
        end

        # @return [String]
        def to_rbs
          field_rbs = fields.keys.map do |key|
            "#{'?' if optional?(key)}#{key_label(key)} #{fields.fetch(key).to_rbs}"
          end
          "{ #{field_rbs.join(', ')} }"
        end

        # @return [Array<Record>]
        def items
          [self]
        end

        # @return [Boolean]
        def undefined?
          false
        end

        # @return [Boolean]
        def void?
          false
        end

        # @return [Boolean]
        def nil_type?
          false
        end

        # @return [Boolean]
        def nullable?
          false
        end

        # @return [Boolean]
        def duck_type?
          false
        end

        # @return [Boolean]
        def literal?
          false
        end

        # @return [Boolean]
        def selfy?
          fields.values.any?(&:selfy?)
        end

        # @return [Boolean]
        def any_generic?
          fields.values.any?(&:any_generic?)
        end

        def all_rooted?
          fields.values.all?(&:all_rooted?)
        end

        # @return [Record]
        def force_rooted
          # @sg-ignore &:method block-pass types a [self] return as the outer receiver
          Record.new(fields.transform_values(&:force_rooted), optional_keys)
        end

        # @param api_map [ApiMap]
        # @param gates [Array<String>]
        # @return [Record]
        def unalias_and_qualify api_map, *gates
          Record.new(fields.transform_values { |type| type.qualify(api_map, *gates) }, optional_keys)
        end

        # @param generics_to_resolve [Enumerable<String>]
        # @param context_type [ComplexType, UniqueType, nil]
        # @param resolved_generic_values [Hash{String => ComplexType, UniqueType}]
        # @return [Record]
        def resolve_generics_from_context generics_to_resolve, context_type, resolved_generic_values: {}
          Record.new(fields.transform_values do |type|
            type.resolve_generics_from_context(generics_to_resolve, context_type,
                                               resolved_generic_values: resolved_generic_values)
          end, optional_keys)
        end

        # @param definitions [Pin::Namespace, Pin::Method]
        # @param context_type [ComplexType]
        # @return [Record]
        def resolve_generics definitions, context_type
          Record.new(fields.transform_values { |type| type.resolve_generics(definitions, context_type) },
                     optional_keys)
        end

        # @param situation [:method_call, :return_type, :assignment]
        # @return [:invariant, :covariant, :contravariant]
        def erased_variance situation = :method_call
          hash_type.erased_variance(situation)
        end

        # @param api_map [ApiMap]
        # @param expected [ComplexType, ComplexType::UniqueType, Record]
        # @param situation [:method_call, :assignment, :return_type]
        # @param rules [Array<Symbol>]
        # @param variance [:invariant, :covariant, :contravariant]
        # @return [Boolean]
        # @sg-ignore https://github.com/castwide/solargraph/pull/1244
        def conforms_to? api_map, expected, situation, rules = [],
                         variance: erased_variance(situation)
          # @sg-ignore https://github.com/castwide/solargraph/pull/1244
          expected.satisfied_by?(self, api_map, situation, rules, variance: variance)
        end

        # A record conforms to a named type as the Hash it describes.
        #
        # @param expected [ComplexType::UniqueType]
        # @param api_map [ApiMap]
        # @param situation [:method_call, :assignment, :return_type]
        # @param rules [Array<Symbol>]
        # @param variance [:invariant, :covariant, :contravariant]
        # @return [Boolean]
        # @sg-ignore https://github.com/castwide/solargraph/pull/1244
        def conforms_to_unique? expected, api_map, situation, rules = [],
                                variance: erased_variance(situation)
          # @sg-ignore https://github.com/castwide/solargraph/pull/1244
          hash_type.conforms_to_unique?(expected, api_map, situation, rules, variance: variance)
        end

        # Another record satisfies this one field by field: it has every
        # required field, and each field it has conforms. Anything else
        # has to satisfy the Hash this record describes.
        #
        # @param inferred [ComplexType, ComplexType::UniqueType, Record]
        # @param api_map [ApiMap]
        # @param situation [:method_call, :assignment, :return_type]
        # @param rules [Array<Symbol>]
        # @param variance [:invariant, :covariant, :contravariant]
        # @return [Boolean]
        def satisfied_by? inferred, api_map, situation, rules = [],
                          variance: inferred.erased_variance(situation)
          unless inferred.is_a?(Record)
            return inferred.conforms_to?(api_map, ComplexType.new([hash_type]), situation, rules,
                                         variance: variance)
          end

          fields.all? do |key, type|
            theirs = inferred.fields[key]
            next optional?(key) if theirs.nil?
            next false if inferred.optional?(key) && !optional?(key)

            theirs.conforms_to?(api_map, type, situation, rules, variance: variance)
          end
        end

        # `[]` gets one overload per field, keyed by the field's literal
        # key; every other method is the Hash's own.
        #
        # @param word [String]
        # @param api_map [ApiMap]
        # @return [::Array<Pin::Base>, nil]
        def method_stack_pins word, api_map
          # @sg-ignore https://github.com/castwide/solargraph/pull/1244
          return hash_type.method_stack_pins(word, api_map) unless word == '[]'

          [field_reader]
        end

        # @param api_map [ApiMap]
        # @param context [String] Fully qualified namespace the type is referenced from
        # @param internal [Boolean] True to include private methods
        # @return [Array<Pin::Base>]
        # @sg-ignore https://github.com/castwide/solargraph/pull/1244
        def candidate_methods_from api_map, context, internal
          # @sg-ignore https://github.com/castwide/solargraph/pull/1244
          hash_type.candidate_methods_from(api_map, context, internal)
        end

        # @param api_map [ApiMap]
        # @param quack [String]
        # @return [Boolean]
        # @sg-ignore https://github.com/castwide/solargraph/pull/1244
        def provides_duck_method? api_map, quack
          # @sg-ignore https://github.com/castwide/solargraph/pull/1244
          hash_type.provides_duck_method?(api_map, quack)
        end

        protected

        def equality_fields
          [fields.to_a, optional_keys.sort_by(&:to_s)]
        end

        private

        # `Hash#[]` with an overload per field: `(:name) -> String` for
        # a required field, `(:port) -> Integer?` for an optional one.
        #
        # @return [Pin::Method]
        def field_reader
          method = Pin::Method.new(name: '[]', closure: Pin::Namespace.new(name: 'Hash'),
                                   signatures: [], source: :rbs)
          fields.each do |key, type|
            return_type = optional?(key) ? ComplexType.new([type, ComplexType::NIL]) : type
            signature = Pin::Signature.new(generics: [], parameters: [], closure: method,
                                           return_type: return_type, source: :rbs)
            signature.parameters << Pin::Parameter.new(name: 'key', closure: signature, source: :rbs,
                                                       return_type: ComplexType.parse(key_literal(key)))
            method.signatures << signature
          end
          method
        end

        # @param key [::Symbol, ::String]
        # @return [String] the key as an RBS literal, e.g. `:name` or `'id'`
        def key_literal key
          key.is_a?(::String) ? "'#{key}'" : key.inspect
        end

        # @param key [::Symbol, ::String]
        # @return [String] `name:` for a plain symbol key, else e.g. `'id' =>`
        def key_label key
          return "#{key}:" if key.is_a?(::Symbol) && key.inspect == ":#{key}"

          "#{key_literal(key)} =>"
        end
      end
    end
  end
end
