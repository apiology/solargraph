# frozen_string_literal: true

describe Solargraph::YardMap::Mapper::ToMethod do
  let(:code_object) do
    namespace = YARD::CodeObjects::ModuleObject.new(nil, 'Example')
    YARD::CodeObjects::MethodObject.new(namespace, 'foo')
  end

  it 'parses args' do
    code_object.parameters = [['bar', nil]]
    pin = described_class.make(code_object)
    param = pin.parameters.first
    expect(param.decl).to be(:arg)
    expect(param.name).to eq('bar')
    expect(param.full).to eq('bar')
  end

  it 'parses optargs' do
    code_object.parameters = [['bar', "'baz'"]]
    pin = described_class.make(code_object)
    param = pin.parameters.first
    expect(param.decl).to be(:optarg)
    expect(param.name).to eq('bar')
    expect(param.full).to eq("bar = 'baz'")
  end

  it 'parses kwargs' do
    code_object.parameters = [['bar:', nil]]
    pin = described_class.make(code_object)
    param = pin.parameters.first
    expect(param.name).to eq('bar')
    expect(param.decl).to be(:kwarg)
    expect(param.full).to eq('bar:')
  end

  it 'parses kwoptargs' do
    code_object.parameters = [['bar:', "'baz'"]]
    pin = described_class.make(code_object)
    param = pin.parameters.first
    expect(param.decl).to be(:kwoptarg)
    expect(param.name).to eq('bar')
    expect(param.full).to eq("bar: 'baz'")
  end

  it 'parses restargs' do
    code_object.parameters = [['*bar', nil]]
    pin = described_class.make(code_object)
    param = pin.parameters.first
    expect(param.decl).to be(:restarg)
    expect(param.name).to eq('bar')
    expect(param.full).to eq('*bar')
  end

  it 'parses kwrestargs' do
    code_object.parameters = [['**bar', nil]]
    pin = described_class.make(code_object)
    param = pin.parameters.first
    expect(param.decl).to be(:kwrestarg)
    expect(param.name).to eq('bar')
    expect(param.full).to eq('**bar')
  end

  it 'parses blockargs' do
    code_object.parameters = [['&bar', nil]]
    pin = described_class.make(code_object)
    param = pin.parameters.first
    expect(param.decl).to be(:blockarg)
    expect(param.name).to eq('bar')
    expect(param.full).to eq('&bar')
  end

  it 'returns self from a constructor made from initialize' do
    namespace = YARD::CodeObjects::ClassObject.new(nil, 'Example')
    initialize = YARD::CodeObjects::MethodObject.new(namespace, 'initialize')
    pin = described_class.make(initialize, 'new', :class)
    expect(pin.return_type.to_s).to eq('self')
  end

  it 'leaves the return type of an explicit self.new undefined' do
    namespace = YARD::CodeObjects::ClassObject.new(nil, 'Example')
    explicit_new = YARD::CodeObjects::MethodObject.new(namespace, 'new', :class)
    pin = described_class.make(explicit_new)
    expect(pin.return_type).to be_undefined
  end

  it 'parses undeclared but typed blockargs' do
    pending('block args coming from YARD alone')

    code_object.parameters = []
    code_object.docstring = <<~EOF
      @yieldparam foo [Integer]
    EOF
    pin = described_class.make(code_object)
    param = pin.parameters.first
    expect(param.decl).to be(:blockarg)
    expect(param.name).to eq('')
    expect(param.full).to eq('&')
  end
end
