# frozen_string_literal: true

require 'open3'
require 'tmpdir'

# A YARD plugin decides what a gem's documentation says, so a workspace
# declaring a different set of them has to be served pins built under its own
# set rather than whichever set reached the cache first.
describe Solargraph::ApiMap do
  # The activesupport-concern plugin lifts this method out of the fixture
  # gem's `class_methods` block. Plain YARD leaves it inside, unreachable.
  let(:path) { 'GemWithConcern::Greeting.greeting' }

  # Conventions are registered per process and the pins are memoized for the
  # life of one, so each declared set is asked in a process of its own.
  #
  # @param directory [String]
  # @param drop_plugin [Boolean]
  # @return [Integer] how many pins the workspace resolves for the path
  def pins_found directory, drop_plugin:
    drop = 'Solargraph::Convention.unregister(Solargraph::Convention::ActiveSupportConcern); '
    script = "require 'solargraph'; #{drop if drop_plugin}" \
             "puts Solargraph::ApiMap.load_with_cache(#{directory.inspect}, nil)" \
             ".get_path_pins(#{path.inspect}).length"
    output, status = Open3.capture2e(RbConfig.ruby, '-e', script)
    raise output unless status.success?

    Integer(output.lines.last)
  end

  before { capture_both { Solargraph::Shell.new.uncache('gem-with-concern') } }

  it 'does not serve pins built under a plugin the workspace has dropped' do
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, 'app.rb'), "require 'gem-with-concern'\n")

      declared = pins_found(directory, drop_plugin: false)
      dropped = pins_found(directory, drop_plugin: true)

      expect([declared, dropped]).to eq([1, 0])
    end
  end
end
