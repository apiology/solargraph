# frozen_string_literal: true

# A YARD plugin decides what a gem's documentation says, so a workspace
# declaring a different set of them has to be served pins built under its own
# set rather than whichever set reached the cache first.
describe Solargraph::Collection::Gem do
  # The activesupport-concern plugin lifts this method out of the fixture
  # gem's `class_methods` block. Plain YARD leaves it inside, unreachable.
  let(:pin_path) { 'GemWithConcern::Greeting.greeting' }
  let(:metagem) { Solargraph::Repo.new(nil).find_by_name('gem-with-concern') }

  # @param metagem [Solargraph::Metagem]
  # @param yard_plugins [Array<String>]
  # @return [Integer] how many pins the gem resolves for the path
  def pins_found metagem, yard_plugins
    described_class.uncache(metagem)
    described_class.load(metagem, yard_plugins).count { |pin| pin.path == pin_path }
  end

  it 'does not serve pins built under a plugin the workspace has dropped' do
    pending 'Not a cacheable gem'
    declared = pins_found(metagem, ['activesupport-concern'])
    dropped = pins_found(metagem, [])

    expect([declared, dropped]).to eq([1, 0])
  end
end
