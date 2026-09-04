# frozen_string_literal: true

require 'stringio'

module Solargraph
  module Diagnostics
    # This reporter provides linting through RuboCop.
    #
    class Rubocop < Base
      include RubocopHelpers

      # Conversion of RuboCop severity names to LSP constants
      SEVERITIES = {
        'info' => Severities::HINT,
        'refactor' => Severities::HINT,
        'convention' => Severities::INFORMATION,
        'warning' => Severities::WARNING,
        'error' => Severities::ERROR,
        'fatal' => Severities::ERROR
      }.freeze

      # @param source [Solargraph::Source]
      # @param _api_map [Solargraph::ApiMap]
      # @return [Array<Hash>]
      def diagnose source, _api_map
        @source = source
        require_rubocop(rubocop_version)
        # @sg-ignore Need to add nil check here
        options, paths = generate_options(source.filename, source.code)
        store = RuboCop::ConfigStore.new
        runner = RuboCop::Runner.new(options, store)
        # Ensure only one instance of RuboCop::Runner is running at
        # a time - it uses 'chdir' to read config files with ERB,
        # which can conflict with other chdirs.
        result = Solargraph::CHDIR_MUTEX.synchronize do
          redirect_stdout { runner.run(paths) }
        end

        return [] if result.empty?

        make_array JSON.parse(result)
      rescue RuboCop::ValidationError, RuboCop::ConfigNotFoundError => e
        raise DiagnosticsError, "Error in RuboCop configuration: #{e.message}"
      rescue JSON::ParserError => e
        raise DiagnosticsError, "RuboCop returned invalid data: #{e.message}"
      end

      private

      # Extracts the rubocop version from _args_
      #
      # @return [String]
      # @sg-ignore Declared return type ::String does not match inferred type ::String, nil for Solargraph::Diagnostics::Rubocop#rubocop_version
      def rubocop_version
        args.find { |a| a =~ /version=/ }.to_s.split('=').last
      end

      # @param resp [Hash{String => Array<Hash{String => Array<Hash{String => undefined}>}>}]
      # @return [Array<Hash>]
      def make_array resp
        diagnostics = []
        # @sg-ignore Unresolved call to each on Array<Hash{String => Array<Hash{String => undefined}>}>, nil
        resp['files'].each do |file|
          file['offenses'].each do |off|
            diagnostics.push offense_to_diagnostic(off)
          end
        end
        diagnostics
      end

      # Convert a RuboCop offense to an LSP diagnostic
      #
      # @param off [Hash{String => unknown}] Offense received from Rubocop
      # @return [Hash{Symbol => Hash, String, Integer}] LSP diagnostic
      def offense_to_diagnostic off
        {
          range: offense_range(off).to_hash,
          # 1 = Error, 2 = Warning, 3 = Information, 4 = Hint
          severity: SEVERITIES[off['severity']],
          source: 'rubocop',
          code: off['cop_name'],
          message: off['message'].gsub(/^#{off['cop_name']}:/, '')
        }
      end

      # @param off [Hash]
      # @return [Range]
      def offense_range off
        Range.new(offense_start_position(off), offense_ending_position(off))
      end

      # @param off [Hash{String => Hash{String => Integer}}]
      # @return [Position]
      def offense_start_position off
        # @sg-ignore Unresolved call to [] on Hash{String => Integer}, nil
        Position.new(off['location']['start_line'] - 1, off['location']['start_column'] - 1)
      end

      # @param off [Hash{String => Hash{String => Integer}}]
      # @return [Position]
      def offense_ending_position off
        # @sg-ignore Unresolved call to [] on Hash{String => Integer}, nil
        if off['location']['start_line'] == off['location']['last_line']
          # @sg-ignore Unresolved call to [] on Hash{String => Integer}, nil
          start_line = off['location']['start_line'] - 1
          # @type [Integer]
          # @sg-ignore Variable type could not be inferred for last_column; Unresolved call to [] on Hash{String => Integer}, nil
          last_column = off['location']['last_column']
          line = @source.code.lines[start_line]
          col_off = if line.nil? || line.empty?
                      1
                    else
                      0
                    end

          # @sg-ignore Wrong argument type for Solargraph::Position.new: character expected Integer, received BigDecimal
          Position.new(
            # @sg-ignore Wrong argument type for Integer#-: arg_0 expected BigDecimal, received Integer
            start_line, last_column - col_off
          )
        else
          # @sg-ignore Unresolved call to [] on Hash{String => Integer}, nil
          Position.new(off['location']['start_line'], 0)
        end
      end
    end
  end
end
