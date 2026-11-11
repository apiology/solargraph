# frozen_string_literal: true

describe Solargraph::Parser do
  def parse source
    Solargraph::Parser.parse(source, 'file.rb', 0)
  end

  it 'parses nodes' do
    node = parse('class Foo; end')
    expect(described_class.is_ast_node?(node)).to be(true)
  end

  it 'raises repairable SyntaxError for unknown encoding errors' do
    code = "# encoding: utf-\nx = 'y'"
    expect { parse(code) }.to raise_error(Solargraph::Parser::SyntaxError)
  end

  # The language server parses from several threads at once (e.g. the
  # diagnoser thread), so each parse must not see another thread's source.
  it 'parses from several threads at once' do
    sources = Array.new(8) do |i|
      body = Array.new(200) { |j| "v#{i}_#{j} = #{j}" }.join("\n")
      "module M#{i}\n  def m\n#{body}\n  end\nend\n"
    end
    expected = sources.map { |source| parse(source) }

    results = sources.map do |source|
      Thread.new { Array.new(20) { parse(source) } }
    end.map(&:value)

    results.each_with_index do |nodes, i|
      expect(nodes).to all(eq(expected[i]))
    end
  end
end
