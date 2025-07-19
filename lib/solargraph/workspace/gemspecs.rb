# frozen_string_literal: true

require 'bundler'

module Solargraph
  class Workspace
    # Manages determining which gemspecs are available in a workspace
    class Gemspecs
      include Logging

      attr_reader :directory, :preferences

      # @param directory [String]
      def initialize directory
        @directory = directory
        # @todo implement preferences
        @preferences = []
      end

      # Take the path given to a 'require' statement in a source file
      # and return the Gem::Specifications which will be brought into
      # scope with it, so we can load pins for them.
      #
      # @param require [String] The string sent to 'require' in the code to resolve, e.g. 'rails', 'bundler/require'
      # @return [::Array<Gem::Specification>, nil]
      def resolve_require require
        return nil if require.empty?
        return auto_required_gemspecs_from_bundler if require == 'bundler/require'

        gemspecs = all_gemspecs_from_bundle
        # @type [Gem::Specification, nil]
        gemspec = gemspecs.find { |gemspec| gemspec.name == require }
        if gemspec.nil?
          # TODO: this seems hinky
          gem_name_guess = require.split('/').first
          begin
            # this can happen when the gem is included via a local path in
            # a Gemfile; Gem doesn't try to index the paths in that case.
            #
            # See if we can make a good guess:
            potential_gemspec = Gem::Specification.find_by_name(gem_name_guess)

            return nil if potential_gemspec.nil?

            file = "lib/#{require}.rb"
            gemspec = potential_gemspec if potential_gemspec&.files&.any? { |gemspec_file| file == gemspec_file }
          rescue Gem::MissingSpecError
            logger.debug do
              "Require path #{require} could not be resolved to a gem via find_by_path or guess of #{gem_name_guess}"
            end
            []
          end
        end
        return nil if gemspec.nil?
        [gemspec_or_preference(gemspec)]
      end

      # @param name [String]
      # @param version [String, nil]
      #
      # @return [Gem::Specification, nil]
      def find_gem name, version
        gemspec = all_gemspecs_from_bundle.find { |gemspec| gemspec.name == name && gemspec.version == version }
        return gemspec if gemspec

        Gem::Specification.find_by_name(name, version)
      rescue Gem::MissingSpecError
        logger.warn "Please install the gem #{name}:#{version} in Solargraph's Ruby environment"
        nil
      end

      # @param gemspec [Gem::Specification]
      # @return [Array<Gem::Specification>]
      def fetch_dependencies gemspec
        raise ArgumentError, 'gemspec must be a Gem::Specification' unless gemspec.is_a?(Gem::Specification)

        gemspecs = all_gemspecs_from_bundle

        # @param runtime_dep [Gem::Dependency]
        # @param deps [Set<Gem::Specification>]
        only_runtime_dependencies(gemspec).each_with_object(Set.new) do |runtime_dep, deps|
          Solargraph.logger.info "Adding #{runtime_dep.name} dependency for #{gemspec.name}"
          dep = gemspecs.find { |dep| dep.name == runtime_dep.name }
          dep ||= Gem::Specification.find_by_name(runtime_dep.name, runtime_dep.requirement)
          deps.merge fetch_dependencies(dep) if deps.add?(dep)
        rescue Gem::MissingSpecError
          Solargraph.logger.warn("Gem dependency #{runtime_dep.name} #{runtime_dep.requirement} " \
                                 "for #{gemspec.name} not found in bundle.")
          nil
        end.to_a.compact
      end

      # Returns all gemspecs directly depended on by this workspace's
      # bundle (does not include transitive dependencies).
      #
      # @return [Array<Gem::Specification>]
      def all_gemspecs_from_bundle
        @all_gemspecs_from_bundle ||=
          if in_this_bundle?
            all_gemspecs_from_this_bundle
          else
            all_gemspecs_from_external_bundle
          end
      end

      private

      # @param command [String] The expression to evaluate in the external bundle
      # @sg-ignore Need a JSON type
      # @yield [undefined]
      def query_external_bundle command, &block
        # TODO: probably combine with logic in require_paths.rb
        Solargraph.with_clean_env do
          cmd = [
            'ruby', '-e',
            "require 'bundler'; require 'json'; Dir.chdir('#{directory}') { puts #{command}.to_json }"
          ]
          # @sg-ignore Unresolved call to capture3
          o, e, s = Open3.capture3(*cmd)
          if s.success?
            Solargraph.logger.debug "External bundle: #{o}"
            data = o && !o.empty? ? JSON.parse(o.split("\n").last) : {}
            block.yield data
          else
            Solargraph.logger.warn e
            raise BundleNotFoundError, "Failed to load gems from bundle at #{directory}"
          end
        end
      end

      def in_this_bundle?
        directory && Bundler.definition&.lockfile&.to_s&.start_with?(directory) # rubocop:disable Style/SafeNavigationChainLength
      end

      # @return [Array<Gem::Specification>]
      def all_gemspecs_from_this_bundle
        # Find only the gems bundler is now using
        specish_objects = Bundler.definition.locked_gems.specs
        if specish_objects.first.respond_to?(:materialize_for_installation)
          specish_objects = specish_objects.map(&:materialize_for_installation)
        end
        specish_objects.map do |specish|
          case specish
          when Gem::Specification
            # yay!
            specish
          when Bundler::LazySpecification
            # materializing didn't work.  Let's look in the local
            # rubygems without bundler's help
            resolve_gem_ignoring_local_bundle specish.name, specish.version
          when Bundler::StubSpecification
            # turns a Bundler::StubSpecification into a
            # Gem::StubSpecification into a Gem::Specification
            specish = specish.stub
            if specish.respond_to?(:spec)
              specish.spec
            else
              resolve_gem_ignoring_local_bundle specish.name, specish.version
            end
          else
            @@warned_on_gem_type ||= false # rubocop:disable Style/ClassVars
            unless @@warned_on_gem_type
              logger.warn "Unexpected type while resolving gem: #{specish.class}"
              @@warned_on_gem_type = true # rubocop:disable Style/ClassVars
            end
          end
        end
      end

      # @return [Array<Gem::Specification>]
      def auto_required_gemspecs_from_bundler
        logger.info 'Fetching gemspecs autorequired from Bundler (bundler/require)'
        @auto_required_gemspecs_from_bundler ||=
          if in_this_bundle?
            auto_required_gemspecs_from_this_bundle
          else
            auto_required_gemspecs_from_external_bundle
          end
      end

      # TODO: "Astute readers will notice that the correct way to
      #   require the rack-cache gem is require 'rack/cache', not
      #   require 'rack-cache'. To tell bundler to use require
      #   'rack/cache', update your Gemfile:"
      #
      # gem 'rack-cache', require: 'rack/cache'

      # @return [Array<Gem::Specification>]
      def auto_required_gemspecs_from_this_bundle
        deps = Bundler.definition.locked_gems.dependencies

        all_gemspecs_from_bundle.select do |gemspec|
          deps.key?(gemspec.name) &&
            deps[gemspec.name].autorequire != []
        end
      end

      # @return [Array<Gem::Specification>]
      def auto_required_gemspecs_from_external_bundle
        @auto_required_gemspecs_from_external_bundle ||=
          begin
            logger.info 'Fetching auto-required gemspecs from Bundler (bundler/require)'
            command =
              'dependencies = Bundler.definition.dependencies; ' \
              'all_specs = Bundler.definition.locked_gems.specs; ' \
              'autorequired_specs = all_specs.' \
              'select { |gemspec| dependencies.key?(gemspec.name) && dependencies[gemspec.name].autorequire != [] }; ' \
              'autorequired_specs.map { |spec| [spec.name, spec.version] }'
            query_external_bundle command do |dependencies|
              dependencies.map do |name, requirement|
                resolve_gem_ignoring_local_bundle name, requirement
              end.compact
            end
          end
      end

      # @param gemspec [Gem::Specification]
      # @return [Array<Gem::Dependency>]
      def only_runtime_dependencies gemspec
        raise ArgumentError, 'gemspec must be a Gem::Specification' unless gemspec.is_a?(Gem::Specification)

        gemspec.dependencies - gemspec.development_dependencies
      end

      # @todo Should this be using Gem::SpecFetcher and pull them automatically?
      #
      # @param name [String]
      # @param version [String]
      # @return [Gem::Specification, nil]
      def resolve_gem_ignoring_local_bundle name, version
        Gem::Specification.find_by_name(name, version)
      rescue Gem::MissingSpecError
        begin
          Gem::Specification.find_by_name(name)
        rescue Gem::MissingSpecError
          logger.warn "Please install the gem #{name}:#{version} in Solargraph's Ruby environment"
          nil
        end
      end

      # @return [Array<Gem::Specification>]
      def all_gemspecs_from_external_bundle
        return [] unless directory

        @all_gemspecs_from_external_bundle ||=
          begin
            logger.info 'Fetching gemspecs required from external bundle'

            command = 'Bundler.definition.locked_gems&.specs&.map { |spec| [spec.name, spec.version] }.to_h'

            query_external_bundle command do |names_and_versions|
              names_and_versions.map do |name, version|
                resolve_gem_ignoring_local_bundle(name, version)
              end.compact
            end
          end
      end

      # @return [Hash{String => Gem::Specification}]
      def preference_map
        @preference_map ||= preferences.to_h { |gemspec| [gemspec.name, gemspec] }
      end

      # @param gemspec [Gem::Specification]
      #
      # @return [Gem::Specification]
      def gemspec_or_preference gemspec
        return gemspec unless preference_map.key?(gemspec.name)
        return gemspec if gemspec.version == preference_map[gemspec.name].version

        change_gemspec_version gemspec, preference_map[gemspec.name].version
      end

      # @param gemspec [Gem::Specification]
      # @param version [String]
      # @return [Gem::Specification]
      def change_gemspec_version gemspec, version
        Gem::Specification.find_by_name(gemspec.name, "= #{version}")
      rescue Gem::MissingSpecError
        Solargraph.logger.info "Gem #{gemspec.name} version #{version} not found. Using #{gemspec.version} instead"
        gemspec
      end
    end
  end
end
