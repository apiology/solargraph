# frozen_string_literal: true

module Solargraph
  class ApiMap
    class Cache
      def initialize
        # @type [Hash{String => Array<Pin::Method>}]
        @methods = {}
        # @type [Hash{String, Array<String> => Array<Pin::Base>}]
        @constants = {}
        # @type [Hash{String => String, nil}]
        @qualified_namespaces = {}
        # @type [Hash{String => Pin::Method}]
        @receiver_definitions = {}
        # @type [Hash{String => SourceMap::Clip}]
        @clips = {}
      end

      def to_s
        self.class.to_s
      end

      # avoid enormous dump
      def inspect
        to_s
      end

      # @param fqns [String]
      # @param scope [Symbol]
      # @param visibility [Array<Symbol>]
      # @param deep [Boolean]
      # @return [Array<Pin::Method>]
      # @sg-ignore Declared return type ::Array<::Solargraph::Pin::Method> does not match inferred type ::Array<::Solargraph::Pin::Method>, nil for Solargraph::ApiMap::Cache#get_methods
      def get_methods fqns, scope, visibility, deep
        @methods["#{fqns}|#{scope}|#{visibility}|#{deep}"]
      end

      # @param fqns [String]
      # @param scope [Symbol]
      # @param visibility [Array<Symbol>]
      # @param deep [Boolean]
      # @param value [Array<Pin::Method>]
      # @return [void]
      def set_methods fqns, scope, visibility, deep, value
        @methods["#{fqns}|#{scope}|#{visibility}|#{deep}"] = value
      end

      # @param namespace [String]
      # @param contexts [Array<String>]
      # @return [Array<Pin::Base>]
      # @sg-ignore Declared return type ::Array<::Solargraph::Pin::Base> does not match inferred type ::Array<::Solargraph::Pin::Base>, nil for Solargraph::ApiMap::Cache#get_constants
      def get_constants namespace, contexts
        @constants["#{namespace}|#{contexts}"]
      end

      # @param namespace [String]
      # @param contexts [Array<String>]
      # @param value [Array<Pin::Base>]
      # @return [void]
      def set_constants namespace, contexts, value
        @constants["#{namespace}|#{contexts}"] = value
      end

      # @param name [String]
      # @param context [String]
      # @return [String, nil]
      # @sg-ignore Declared return type ::String, nil does not match inferred type ::String, ::NilClass, nil for Solargraph::ApiMap::Cache#get_qualified_namespace
      def get_qualified_namespace name, context
        @qualified_namespaces["#{name}|#{context}"]
      end

      # @param name [String]
      # @param context [String]
      # @param value [String, nil]
      # @return [void]
      def set_qualified_namespace name, context, value
        # @sg-ignore Wrong argument type for Hash#[]=: arg1 expected String, NilClass, received String, nil
        @qualified_namespaces["#{name}|#{context}"] = value
      end

      # @param path [String]
      # @return [Pin::Method]
      # @sg-ignore Declared return type ::Solargraph::Pin::Method does not match inferred type ::Solargraph::Pin::Method, nil for Solargraph::ApiMap::Cache#get_receiver_definition
      def get_receiver_definition path
        @receiver_definitions[path]
      end

      # @param path [String]
      # @param pin [Pin::Method]
      # @return [void]
      def set_receiver_definition path, pin
        @receiver_definitions[path] = pin
      end

      # @return [void]
      def clear
        return if empty?

        all_caches.each(&:clear)
      end

      # @return [Boolean]
      def empty?
        all_caches.all?(&:empty?)
      end

      private

      # @return [Array<Object>]
      def all_caches
        [@methods, @constants, @qualified_namespaces, @receiver_definitions, @clips]
      end
    end
  end
end
