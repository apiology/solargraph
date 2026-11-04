# frozen_string_literal: true

describe Solargraph::Pin::Callable do
  describe '#return_type!' do
    let(:namespace) { Solargraph::Pin::Namespace.new(name: 'Foo') }
    let(:method_pin) do
      Solargraph::Pin::Method.new(name: 'bar', closure: namespace, scope: :instance)
    end

    it 'hands back the established return type' do
      return_type = Solargraph::ComplexType.parse('String')
      pin = Solargraph::Pin::Signature.new(closure: method_pin, return_type: return_type)

      expect(pin.return_type!).to be(return_type)
    end

    it 'raises naming the callable, rather than describing the type it does not have' do
      pin = Solargraph::Pin::Signature.new(closure: method_pin)

      expect { pin.return_type! }
        .to raise_error(RuntimeError, 'No return type set on Solargraph::Pin::Signature Foo#bar')
    end
  end
end
