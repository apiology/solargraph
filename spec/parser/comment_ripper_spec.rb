# frozen_string_literal: true

describe Solargraph::Parser::CommentRipper do
  it 'maps comments that start a line' do
    comments = described_class.new("x = 1\n# a\ny = 2 # b\n").parse
    expect(comments.keys).to eq([1])
  end

  it 'raises when lineno shifts a comment past the end of the source' do
    ripper = described_class.new("x = 1\n# a\n", '(x)', 1)
    expect { ripper.parse }.to raise_error(RuntimeError, /past the end of the source/)
  end
end
