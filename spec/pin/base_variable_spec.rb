# frozen_string_literal: true

describe Solargraph::Pin::BaseVariable do
  it 'checks assignments for equality' do
    smap = Solargraph::SourceMap.load_string('foo = "foo"')
    pin1 = smap.locals.first
    smap = Solargraph::SourceMap.load_string('foo = "foo"')
    pin2 = smap.locals.first
    expect(pin1).to eq(pin2)
    smap = Solargraph::SourceMap.load_string('foo = "bar"')
    pin2 = smap.locals.first
    expect(pin1).not_to eq(pin2)
  end

  it 'treats combine_with results with the same location but different presence as unequal' do
    # combine_with results choose the earliest assignment's #location,
    # so two combine_with results over a different number of
    # assignments to the same variable can share #location while
    # covering different #presence ranges. Pin::Base#== only compared
    # location, not presence, so these looked equal to any caller
    # keying off of #== (e.g. Array#include?, used by Chain's inference
    # recursion guard) even though they represent different sets of
    # possible values for the variable.
    source = Solargraph::Source.load_string(%(
      def go(str)
        str = str.gsub('a', 'b')
        str = str.gsub('c', 'd')
        str
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source
    smap = api_map.source_map('test.rb')
    param = smap.locals.find { |p| p.name == 'str' && p.is_a?(Solargraph::Pin::Parameter) }
    first_assignment = smap.locals.find { |p| p.name == 'str' && p.location.range.start.line == 2 }
    second_assignment = smap.locals.find { |p| p.name == 'str' && p.location.range.start.line == 3 }

    combined_through_first = param.combine_with(first_assignment)
    combined_through_second = combined_through_first.combine_with(second_assignment)

    expect(combined_through_first.location).to eq(combined_through_second.location)
    expect(combined_through_first.presence).not_to eq(combined_through_second.presence)
    expect(combined_through_first).not_to eq(combined_through_second)
  end

  it 'infers types from variable assignments with unparenthesized parameters' do
    source = Solargraph::Source.load_string(%(
      class Container
        def initialize; end
      end
      cnt = Container.new param1, param2
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source
    pin = api_map.source_map('test.rb').locals.first
    type = pin.probe(api_map)
    expect(type.tag).to eq('Container')
  end

  it 'infers from nil nodes without locations' do
    source = Solargraph::Source.load_string(%(
      class Foo
        def bar
          @bar =
            if baz
              1
            end
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source
    pin = api_map.get_instance_variable_pins('Foo').first
    type = pin.probe(api_map)
    expect(type.tags).to eq('1, nil')
    expect(type.simple_tags).to eq('Integer, nil')
    expect(type.to_rbs).to eq('(1 | nil)')
    expect(type.simplify_literals.to_rbs).to eq('(::Integer | nil)')
  end

  it 'infers a splat target in a multiple assignment as an array' do
    source = Solargraph::Source.load_string(%(
      class Repro
        # @param mutator [Array<Symbol, BasicObject>]
        # @return [void]
        def call(mutator)
          command, *args = mutator
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source
    locals = api_map.source_map('test.rb').locals
    command_pin = locals.find { |l| l.name == 'command' }
    args_pin = locals.find { |l| l.name == 'args' }
    expect(command_pin.probe(api_map).tag).to eq('Symbol')
    expect(args_pin.probe(api_map).tag).to eq('Array<Symbol, BasicObject>')
  end

  it 'infers a splat target of a non-collection type as undefined' do
    source = Solargraph::Source.load_string(%(
      class Repro
        # @param mutator [Integer]
        # @return [void]
        def call(mutator)
          command, *args = mutator
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source
    locals = api_map.source_map('test.rb').locals
    args_pin = locals.find { |l| l.name == 'args' }
    expect(args_pin.probe(api_map)).to be_undefined
  end

  it 'infers a splat target from a user-defined class that includes Enumerable' do
    source = Solargraph::Source.load_string(%(
      # @generic Elem
      class MyBag
        include Enumerable

        # @yieldparam [generic<Elem>]
        # @return [void]
        def each; end
      end

      class Repro
        # @param bag [MyBag<String>]
        # @return [void]
        def call(bag)
          first, *rest = bag
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source
    locals = api_map.source_map('test.rb').locals
    first_pin = locals.find { |l| l.name == 'first' }
    rest_pin = locals.find { |l| l.name == 'rest' }
    expect(first_pin.probe(api_map).tag).to eq('String')
    expect(rest_pin.probe(api_map).tag).to eq('Array<String>')
  end

  it 'gives every non-splat target the full element union of a non-tuple Array' do
    # #to_s, not #tag, so a regression collapsing the union to one member fails here.
    source = Solargraph::Source.load_string(%(
      class Repro
        # @param pair [Array<Integer, String>]
        # @return [void]
        def call(pair)
          a, b = pair
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source
    locals = api_map.source_map('test.rb').locals
    a_pin = locals.find { |l| l.name == 'a' }
    b_pin = locals.find { |l| l.name == 'b' }
    expect(a_pin.probe(api_map).to_s).to eq('Integer, String')
    expect(b_pin.probe(api_map).to_s).to eq('Integer, String')
  end

  it 'infers an undefined splat target when the source is not itself a tuple or container' do
    source = Solargraph::Source.load_string(%(
      class Repro
        # @param mutator [Integer]
        # @return [void]
        def call(mutator)
          command, *args = mutator
        end
      end
    ), 'test.rb')
    api_map = Solargraph::ApiMap.new
    api_map.map source
    locals = api_map.source_map('test.rb').locals
    args_pin = locals.find { |l| l.name == 'args' }
    expect(args_pin.probe(api_map).tag).to eq('undefined')
  end

  it 'treats downcasts with the same presence but different narrowed_return_type as unequal' do
    smap = Solargraph::SourceMap.load_string('foo = "foo"')
    pin = smap.locals.first
    narrowed_int = pin.downcast(presence: pin.presence, narrowed_return_type: Solargraph::ComplexType.parse('Integer'))
    narrowed_str = pin.downcast(presence: pin.presence, narrowed_return_type: Solargraph::ComplexType.parse('String'))
    expect(narrowed_int.eql?(narrowed_str)).to be(false)
  end

  it 'treats downcasts with the same presence but different exclude_return_type as unequal' do
    smap = Solargraph::SourceMap.load_string('foo = "foo"')
    pin = smap.locals.first
    excludes_int = pin.downcast(presence: pin.presence, exclude_return_type: Solargraph::ComplexType.parse('Integer'))
    excludes_str = pin.downcast(presence: pin.presence, exclude_return_type: Solargraph::ComplexType.parse('String'))
    expect(excludes_int.eql?(excludes_str)).to be(false)
  end

  it "understands proc kwarg parameters aren't affected by @type" do
    code = %(
      # @return [Proc]
      def foo
        # @type [Proc]
        # @param layout [Boolean]
        @render_method = proc { |layout = false|
          123 if layout
        }
      end
    )
    checker = Solargraph::TypeChecker.load_string(code, 'test.rb', :alpha)
    expect(checker.problems.map(&:message)).to eq([])
  end

  it 'includes presence and narrowed/exclude return type in #eql? and #hash' do
    # Equality#eql?/#hash (used by Array#uniq, Set, and Hash keys) key off
    # of #equality_fields. Flow-sensitive typing downcasts a pin into
    # copies that share name/location/closure/source but differ in
    # presence/narrowed_return_type/exclude_return_type - those copies
    # must stay distinct as eql?/hash keys.
    location = Solargraph::Location.new('test.rb', Solargraph::Range.from_to(0, 0, 1, 0))
    presence1 = Solargraph::Range.from_to(0, 0, 0, 5)
    presence2 = Solargraph::Range.from_to(1, 0, 1, 5)
    pin1 = Solargraph::Pin::LocalVariable.new(name: 'foo', location: location, presence: presence1)
    pin2 = Solargraph::Pin::LocalVariable.new(name: 'foo', location: location, presence: presence2)
    expect(pin1.eql?(pin2)).to be(false)
    expect(pin1.hash).not_to eq(pin2.hash)
  end

  it 'includes narrowed/exclude return type in #equality_fields' do
    location = Solargraph::Location.new('test.rb', Solargraph::Range.from_to(0, 0, 1, 0))
    presence = Solargraph::Range.from_to(0, 0, 0, 5)
    pin = Solargraph::Pin::LocalVariable.new(name: 'foo', location: location)
    downcast1 = pin.downcast(presence: presence, narrowed_return_type: Solargraph::ComplexType.parse('String'))
    downcast2 = pin.downcast(presence: presence, exclude_return_type: Solargraph::ComplexType.parse('Integer'))
    expect(downcast1.send(:equality_fields)).not_to eq(downcast2.send(:equality_fields))
  end
end
