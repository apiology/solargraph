# frozen_string_literal: true

describe Solargraph::Parser do
  it 'parses nodes' do
    node = described_class.parse('class Foo; end', 'test.rb')
    expect(described_class.is_ast_node?(node)).to be(true)
  end

  it 'raises repairable SyntaxError for unknown encoding errors' do
    code = "# encoding: utf-\nx = 'y'"
    expect { described_class.parse(code) }.to raise_error(Solargraph::Parser::SyntaxError)
  end
end
