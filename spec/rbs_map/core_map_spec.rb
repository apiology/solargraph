describe Solargraph::RbsMap::CoreMap do
  it 'maps core Errno classes' do
    map = Solargraph::RbsMap::CoreMap.new
    store = Solargraph::ApiMap::Store.new(map.pins)
    Errno.constants.each do |const|
      pin = store.get_path_pins("Errno::#{const}").first
      expect(pin).to be_a(Solargraph::Pin::Namespace)
      superclass = store.get_superclass(pin.path)
      expect(superclass).to eq('SystemCallError')
    end
  end

  it 'understands RBS class aliases' do
    map = Solargraph::RbsMap::CoreMap.new
    store = Solargraph::ApiMap::Store.new(map.pins)
    # The core RBS contains:
    #   class Mutex = Thread::Mutex
    thread_mutex_pin = store.get_path_pins("Thread::Mutex").first
    expect(thread_mutex_pin).to be_a(Solargraph::Pin::Namespace)

    mutex_pin = store.get_path_pins("Mutex").first
    expect(mutex_pin).to be_a(Solargraph::Pin::Constant)
    expect(mutex_pin.return_type.to_s).to eq("Class<Thread::Mutex>")
  end


  it 'understands RBS global variables' do
    map = Solargraph::RbsMap::CoreMap.new
    store = Solargraph::ApiMap::Store.new(map.pins)
    global_variable_pins = store.pins_by_class(Solargraph::Pin::GlobalVariable)
    stderr_pins = global_variable_pins.select do |pin|
      pin.name == '$stderr'
    end
    expect(stderr_pins.map(&:class)).to eq([Solargraph::Pin::GlobalVariable])
    stderr_pin = stderr_pins.first
    expect(stderr_pin.return_type.to_s).to eq('IO')
  end

  it 'understands implied Enumerator#each method' do
    api_map = Solargraph::ApiMap.new
    methods = api_map.get_methods('Enumerable')
    each_pins = methods.select{|pin| pin.path.end_with?('#each')}
    # expect this to come from the _Each implied interface ("self
    # type") defined in the RBS
    expect(each_pins.map(&:path)).to eq(["_Each#each"])
    expect(each_pins.map(&:class)).to eq([Solargraph::Pin::Method])
    each_pin = each_pins.first
    expect(each_pin.signatures.length).to eq(1)
    signature = each_pin.signatures.first
    expect(signature.block.return_type.to_s).to eq('void')
  end
end
