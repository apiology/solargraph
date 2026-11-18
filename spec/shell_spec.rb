# frozen_string_literal: true

require 'tmpdir'
require 'open3'

describe Solargraph::Shell do
  let(:shell) { described_class.new }

  describe '--version' do
    it 'returns a version when run' do
      output = capture_stdout do
        shell.version
      end

      expect(output).to eq("#{Solargraph::VERSION}\n")
    end
  end

  describe 'uncache' do
    it 'uncaches without erroring out' do
      allow(Solargraph::Collection::Gem).to receive(:uncache)

      capture_stdout do
        shell.uncache('public_suffix')
      end

      expect(Solargraph::Collection::Gem).to have_received(:uncache)
    end

    it 'uncaches stdlib without erroring out' do
      allow(FileUtils).to receive(:rm_rf)

      capture_stdout do
        shell.uncache('stdlib')
      end

      expect(FileUtils).to have_received(:rm_rf).with(Solargraph::CacheDir.stdlib_dir)
    end

    it 'uncaches core without erroring out' do
      allow(Solargraph::Collection::Core).to receive(:uncache)

      capture_stdout do
        shell.uncache('core')
      end

      expect(Solargraph::Collection::Core).to have_received(:uncache)
    end
  end

  describe 'scan' do
    context 'with mocked dependencies' do
      let(:api_map) { instance_double(Solargraph::ApiMap) }

      before do
        allow(Solargraph::ApiMap).to receive(:load_with_cache).and_return(api_map)
      end

      it 'scans without erroring out' do
        allow(api_map).to receive(:pins).and_return([])
        output = capture_stdout do
          shell.options = { directory: 'spec/fixtures/workspace' }
          shell.scan
        end

        expect(output).to include('Scanned ').and include(' seconds.')
      end
    end
  end

  describe 'typecheck' do
    context 'with mocked dependencies' do
      let(:type_checker) { instance_double(Solargraph::TypeChecker) }
      let(:api_map) { instance_double(Solargraph::ApiMap) }

      before do
        allow(Solargraph::ApiMap).to receive(:load_with_cache).and_return(api_map)
        allow(Solargraph::TypeChecker).to receive(:new).and_return(type_checker)
        allow(type_checker).to receive(:problems).and_return([])
      end

      it 'typechecks without erroring out' do
        output = capture_stdout do
          shell.options = { level: 'normal', directory: '.' }
          shell.typecheck('Gemfile')
        end

        expect(output).to include('Typecheck finished in')
      end
    end
  end

  describe 'gems' do
    context 'without mocked ApiMap' do
      it 'complains when gem does not exist' do
        skip 'WIP'
        output = capture_both do
          shell.gems('nonexistentgem')
        end

        expect(output).to include("Gem 'nonexistentgem' not found")
      end

      it 'caches core without erroring out' do
        skip 'WIP'
        capture_both do
          shell.uncache('core')
        end

        expect { shell.cache('core') }.not_to raise_error
      end

      it 'gives sensible error for gem that does not exist' do
        skip 'WIP'
        output = capture_both do
          shell.gems('solargraph123')
        end

        expect(output).to include("Gem 'solargraph123' not found")
      end
    end

    context 'with mocked Repo' do
      let(:repo) { instance_double(Solargraph::Repo) }
      let(:metagem) do
        instance_double(Solargraph::Metagem, name: 'abcd343kfk', version: '1.0.0',
                                             cache_name: 'abcd343kfk-1.0.0', cacheable?: true)
      end

      before do
        allow(Solargraph::Repo).to receive(:new).and_return(repo)
        allow(Solargraph::Collection::Gem).to receive(:load_all)
      end

      it 'caches all without erroring out' do
        allow(repo).to receive_messages(bundled?: true, bundled: [metagem])

        capture_both do
          shell.options = { rebuild: false }
          shell.cache
        end

        expect(Solargraph::Collection::Gem).to have_received(:load_all).with([metagem], out: anything, rebuild: false)
      end

      it 'falls back to every installed gem outside a bundle' do
        allow(repo).to receive(:bundled?).and_return(false)
        gemspec = Gem::Specification.find_by_name('backport')
        allow(Gem::Specification).to receive_messages(all_names: ['backport-1.2.0'],
                                                      find_by_full_name: gemspec)
        allow(Solargraph::Metagem).to receive(:from_specification).with(gemspec).and_return(metagem)

        output = capture_both do
          shell.options = { rebuild: false }
          shell.cache
        end

        expect(output).to include('Caching abcd343kfk 1.0.0 (abcd343kfk-1.0.0)')
        expect(Solargraph::Collection::Gem).to have_received(:load_all).with([metagem], out: anything, rebuild: false)
      end

      it 'rebuilds core when named alongside a rebuild' do
        allow(Solargraph::Collection::Core).to receive(:uncache)
        allow(Solargraph::Collection::Core).to receive(:load)

        output = capture_both do
          shell.options = { rebuild: true }
          shell.cache('core')
        end

        expect(output).to include('Caching core')
        expect(Solargraph::Collection::Core).to have_received(:uncache)
        expect(Solargraph::Collection::Core).to have_received(:load)
      end

      it 'loads core without discarding it when not rebuilding' do
        allow(Solargraph::Collection::Core).to receive(:uncache)
        allow(Solargraph::Collection::Core).to receive(:load)

        capture_both do
          shell.options = { rebuild: false }
          shell.cache('core')
        end

        expect(Solargraph::Collection::Core).not_to have_received(:uncache)
        expect(Solargraph::Collection::Core).to have_received(:load)
      end

      it 'caches single gem without erroring out' do
        allow(repo).to receive(:find_by_name).with('98765').and_return(metagem)

        capture_both do
          shell.options = { rebuild: false }
          shell.cache('98765')
        end

        expect(Solargraph::Collection::Gem).to have_received(:load_all).with([metagem], out: anything, rebuild: false)
      end
    end
  end

  context 'with a plugin configured in the workspace' do
    let(:temp_dir) { Dir.mktmpdir }
    let(:plugin_dir) { Dir.mktmpdir }

    before do
      File.write(File.join(plugin_dir, 'cache_probe_plugin.rb'), '')
      File.write(File.join(temp_dir, '.solargraph.yml'), "plugins:\n  - cache_probe_plugin\n")
      $LOAD_PATH.unshift plugin_dir
    end

    after do
      $LOAD_PATH.delete plugin_dir
      $LOADED_FEATURES.delete_if { |path| path.end_with?('cache_probe_plugin.rb') }
      Solargraph::CacheDir.plugins.delete 'cache_probe_plugin'
      Solargraph::CacheDir.plugin_requires.delete 'cache_probe_plugin'
      FileUtils.rm_rf plugin_dir
      FileUtils.rm_rf temp_dir
    end

    it 'loads the plugin before caching' do
      capture_both { described_class.new([], directory: temp_dir).cache('nonexistentgem8675309') }
      expect($LOADED_FEATURES).to include(end_with('cache_probe_plugin.rb'))
    end

    it 'loads the plugin before uncaching' do
      capture_both { described_class.new([], directory: temp_dir).uncache('nonexistentgem8675309') }
      expect($LOADED_FEATURES).to include(end_with('cache_probe_plugin.rb'))
    end

    it 'loads the plugins it is given instead of the configured ones' do
      capture_both { described_class.new([], directory: temp_dir, plugins: '').cache('nonexistentgem8675309') }
      expect($LOADED_FEATURES).not_to include(end_with('cache_probe_plugin.rb'))
    end

    it 'loads and records the plugins it is given' do
      capture_both { described_class.new([], directory: temp_dir, plugins: 'cache_probe_plugin').cache('nonexistentgem8675309') }
      expect(Solargraph::CacheDir.plugin_requires).to include('cache_probe_plugin')
    end

    it 'warns about a plugin it cannot load' do
      allow(Solargraph.logger).to receive(:warn)
      capture_both { described_class.new([], directory: temp_dir, plugins: 'missing_probe_plugin').cache('nonexistentgem8675309') }
      expect(Solargraph.logger).to have_received(:warn).with("Failed to load plugin 'missing_probe_plugin'")
    end
  end

  describe 'cache' do
    it 'caches a stdlib gem without erroring out' do
      skip 'WIP'
      expect { shell.cache('stringio') }.not_to raise_error
    end

    context 'when gem does not exist' do
      subject(:call) { shell.cache('nonexistentgem8675309') }

      it 'gives a good error message' do
        # capture stderr output
        expect { call }.to output(/not found/).to_stderr
      end
    end
  end

  describe 'pin on a class' do
    let(:api_map) { instance_double(Solargraph::ApiMap) }
    let(:string_pin) { instance_double(Solargraph::Pin::Namespace, name: 'String') }

    before do
      allow(Solargraph::ApiMap).to receive(:load_with_cache).and_return(api_map)
      allow(Solargraph::Pin::Namespace).to receive(:===).with(string_pin).and_return(true)
      allow(string_pin).to receive(:return_type).and_return(Solargraph::ComplexType.parse('String'))
      allow(api_map).to receive(:get_path_pins).with('String').and_return([string_pin])
    end

    context 'with --references option' do
      let(:object_pin) { instance_double(Solargraph::Pin::Namespace, name: 'Object') }

      before do
        allow(Solargraph::Pin::Namespace).to receive(:===).with(object_pin).and_return(true)
        allow(api_map).to receive(:qualify_superclass).with('String').and_return('Object')
        allow(api_map).to receive(:get_path_pins).with('Object').and_return([object_pin])
      end

      it 'prints a pin with info' do
        out = capture_both do
          shell.options = { references: true }
          shell.pin('String')
        end
        expect(out).to include('# Superclass:')
      end
    end
  end

  describe 'pin on a method' do
    let(:api_map) { instance_double(Solargraph::ApiMap) }
    let(:to_s_pin) { instance_double(Solargraph::Pin::Method, return_type: Solargraph::ComplexType.parse('String')) }

    before do
      allow(Solargraph::Pin::Method).to receive(:===).with(to_s_pin).and_return(true)
      allow(Solargraph::ApiMap).to receive(:load_with_cache).and_return(api_map)
      allow(api_map).to receive(:get_path_pins).with('String#to_s').and_return([to_s_pin])
    end

    context 'with no options' do
      it 'prints a pin' do
        allow(to_s_pin).to receive(:inspect).and_return('pin inspect result')

        out = capture_both { shell.pin('String#to_s') }

        expect(out).to eq("pin inspect result\n")
      end
    end

    context 'with --rbs option' do
      it 'prints a pin with RBS type' do
        allow(to_s_pin).to receive(:to_rbs).and_return('pin RBS result')

        out = capture_both do
          shell.options = { rbs: true }
          shell.pin('String#to_s')
        end
        expect(out).to eq("pin RBS result\n")
      end
    end

    context 'with --stack option' do
      it 'prints a pin using stack results' do
        allow(to_s_pin).to receive(:to_rbs).and_return('pin RBS result')

        allow(api_map).to receive(:get_method_stack).and_return([to_s_pin])
        capture_both do
          shell.options = { stack: true }
          shell.pin('String#to_s')
        end
        expect(api_map).to have_received(:get_method_stack).with('String', 'to_s', scope: :instance)
      end

      it 'prints a static pin using stack results' do
        # allow(to_s_pin).to receive(:to_rbs).and_return('pin RBS result')
        string_new_pin = instance_double(Solargraph::Pin::Method, return_type: Solargraph::ComplexType.parse('String'))

        allow(api_map).to receive(:get_method_stack).with('String', 'new', scope: :class).and_return([string_new_pin])
        allow(Solargraph::Pin::Method).to receive(:===).with(string_new_pin).and_return(true)
        allow(api_map).to receive(:get_path_pins).with('String.new').and_return([string_new_pin])
        capture_both do
          shell.options = { stack: true }
          shell.pin('String.new')
        end
        expect(api_map).to have_received(:get_method_stack).with('String', 'new', scope: :class)
      end
    end

    context 'with --typify option' do
      it 'prints a pin with typify type' do
        allow(to_s_pin).to receive(:typify).and_return(Solargraph::ComplexType.parse('::String'))

        out = capture_both do
          shell.options = { typify: true }
          shell.pin('String#to_s')
        end
        expect(out).to eq("::String\n")
      end
    end

    context 'with --typify --rbs options' do
      it 'prints a pin with typify type' do
        allow(to_s_pin).to receive(:typify).and_return(Solargraph::ComplexType.parse('::String'))

        out = capture_both do
          shell.options = { typify: true, rbs: true }
          shell.pin('String#to_s')
        end
        expect(out).to eq("::String\n")
      end
    end

    context 'with no pin' do
      it 'prints error' do
        allow(api_map).to receive(:get_path_pins).with('Not#found').and_return([])
        allow(Solargraph::Pin::Method).to receive(:===).with(nil).and_return(false)

        out = capture_both do
          shell.options = {}
          shell.pin('Not#found')
        rescue SystemExit
          # Ignore the SystemExit raised by the shell when no pin is found
        end
        expect(out).to include("Pin not found for path 'Not#found'")
      end
    end
  end

  describe 'profile' do
    # vernier is an optional dependency (see the LoadError rescue in
    # Shell#profile) and isn't installed in this repo's Gemfile, so stub it
    # out entirely rather than requiring the real gem.
    before do
      allow(shell).to receive(:require).with('vernier').and_return(true)
      stub_const('Vernier', Module.new)
      allow(Vernier).to receive(:profile).and_yield
    end

    it 'profiles go-to-definition against a real workspace' do
      Dir.mktmpdir do |output_dir|
        output = capture_both do
          shell.options = { directory: 'spec/fixtures/workspace', output_dir: output_dir, line: 4, column: 10 }
          shell.profile
        end

        expect(output).to include('Processing go-to-definition request...')
        expect(output).to include('Result: [{')
        expect(output).to include('uri')
        expect(output).to include('thing.rb"')
      end
    end

    it 'explains how to install vernier when it is missing' do
      allow(shell).to receive(:require).with('vernier').and_raise(LoadError)

      output = capture_both { shell.profile }

      expect(output).to include("gem 'vernier'")
    end

    it 'stops when the workspace has no Ruby files' do
      Dir.mktmpdir do |dir|
        Dir.mktmpdir do |output_dir|
          output = capture_both do
            shell.options = { directory: dir, output_dir: output_dir, line: 0, column: 0 }
            shell.profile
          end

          expect(output).to include('No Ruby files found in workspace')
        end
      end
    end

    it 'finishes and lists saved profiles after CTRL-C' do
      handler = nil
      allow(Signal).to receive(:trap) do |*_args, &block|
        handler = block if block
        'DEFAULT'
      end
      allow(Process).to receive(:kill)
      allow(Vernier).to receive(:profile) { handler.call }

      Dir.mktmpdir do |output_dir|
        File.write(File.join(output_dir, 'parse_benchmark.json.gz'), '')
        output = capture_both do
          shell.options = { directory: 'spec/fixtures/workspace', output_dir: output_dir, line: 4, column: 10 }
          shell.profile
        end
        # A second CTRL-C restores the default handler and re-sends the signal
        handler.call

        expect(output).to include('Profile run interrupted')
        expect(output).to include('Profiles saved to:')
        expect(Process).to have_received(:kill).with('INT', Process.pid)
      end
    end
  end

  describe 'profile_test_file' do
    it 'uses the given file' do
      expect(shell.send(:profile_test_file, '/ws', 'a.rb')).to eq('/ws/a.rb')
    end

    it 'falls back to any Ruby file in the workspace' do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, 'app.rb'), '')

        expect(shell.send(:profile_test_file, dir, nil)).to end_with('app.rb')
      end
    end
  end

  context 'with unbundled environments' do
    let!(:command_path) { File.realpath(File.join('spec', 'fixtures', 'shim.rb')) }
    let!(:unbundled_env) { Bundler.unbundled_env.merge({ 'BUNDLE_GEMFILE' => nil }) }

    describe '#cache' do
      it 'succeeds' do
        skip 'WIP'
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'test.rb'), 'foo')
          _o, e, s = Open3.capture3(unbundled_env, 'ruby', command_path, 'cache', 'rspec', chdir: tmpdir)
          expect(s).to be_success, "expected success, got error with message #{e.inspect}"
        end
      end
    end

    describe '#gems' do
      it 'succeeds' do
        skip 'WIP'
        Dir.mktmpdir do |tmpdir|
          File.write(File.join(tmpdir, 'test.rb'), 'foo')
          _o, e, s = Open3.capture3(unbundled_env, 'ruby', command_path, 'gems', 'rspec', chdir: tmpdir)
          expect(s).to be_success, "expected success, got error with message #{e.inspect}"
        end
      end
    end

    describe 'rbs' do
      let(:api_map) { instance_double(Solargraph::ApiMap) }

      before do
        allow(shell).to receive(:`)
        allow(Solargraph::ApiMap).to receive(:load).and_return(api_map)
        allow(api_map).to receive(:source_maps).and_return(source_maps)
      end

      context 'without inference' do
        let(:source_maps) { [] }

        it 'invokes sord' do
          capture_both do
            shell.options = { filename: 'foo.rbs' }
            shell.rbs
          end
          expect(shell)
            .to have_received(:`)
            .with("sord #{Dir.pwd}/sig/foo.rbs --rbs --no-regenerate")
        end
      end

      context 'with inference' do
        let(:source_maps) { [source_map] }
        let(:source_map) { instance_double(Solargraph::SourceMap) }
        let(:pin) do
          instance_double(Solargraph::Pin::Method,
                          namespace: 'My::Namespace', path: 'My::Namespace#foo',
                          visibility: :public,
                          parameters: [],
                          scope: :instance,
                          location: nil,
                          name: 'foo',
                          class: Solargraph::Pin::Method,
                          return_type: Solargraph::ComplexType::UNDEFINED)
        end

        it 'infers unknown types on pins' do
          allow(source_map).to receive(:pins).and_return([pin])
          allow(pin).to receive_messages(typify: Solargraph::ComplexType.parse('String'),
                                         docstring: YARD::Docstring.new(''), macros: [])
          allow(pin).to receive(:code_object).and_return(nil)
          capture_both do
            shell.options = { filename: 'foo.rbs', inference: true }
            shell.rbs
          end
          expect(pin).to have_received(:typify)
        end
      end
    end
  end
end
