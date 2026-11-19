# frozen_string_literal: true

describe Solargraph::Source::Chain::MatchGroup do
  # @param body [String] method body; its last line is inferred
  # @param params [String] extra method parameters
  # @return [String]
  def infer_last_line body, params = ''
    code = "# @param s [String]\n# @param r [Regexp]\ndef foo(s, r#{params})\n#{body}\nend\n"
    api_map = Solargraph::ApiMap.new
    api_map.map Solargraph::Source.load_string(code, 'test.rb')
    line = code.lines.length - 2
    api_map.clip_at('test.rb', [line, code.lines[line].rstrip.length]).infer.rooted_tags
  end

  it 'treats group 0 of any MatchData as non-nil' do
    expect(infer_last_line("md = s.match(r)\nmd[0]")).to eq('::String')
  end

  it 'treats a required group as non-nil' do
    expect(infer_last_line("md = s.match(/(a)(b)?/)\nmd[1]")).to eq('::String')
  end

  it 'treats a required group as non-nil through safe navigation' do
    expect(infer_last_line("md = s&.match(/x(a)/i)\nreturn unless md\nmd[1]")).to eq('::String')
  end

  it 'treats a required group of an inline match as non-nil' do
    expect(infer_last_line('s.match(/(a)/)[1]')).to eq('::String')
  end

  it 'keeps a named group nilable' do
    expect(infer_last_line("md = s.match(/(?<a>a)/)\nmd[:a]")).to eq('::String, nil')
  end

  it 'keeps an optional group nilable' do
    expect(infer_last_line("md = s.match(/(a)(b)?/)\nmd[2]")).to eq('::String, nil')
  end

  it 'keeps an alternation group nilable' do
    expect(infer_last_line("md = s.match(/(a)|b/)\nmd[1]")).to eq('::String, nil')
  end

  it 'keeps a group of a non-literal regexp nilable' do
    expect(infer_last_line("md = s.match(r)\nmd[1]")).to eq('::String, nil')
  end

  it 'keeps a group nilable when the variable is not assigned from String#match' do
    expect(infer_last_line("md = r.match(s)\nmd[1]")).to eq('::String, nil')
  end

  it 'keeps a group nilable when one assignment is not a call' do
    expect(infer_last_line("md = s.match(/(a)/)\nmd = nil if s.empty?\nmd[1]")).to eq('::String, nil')
  end

  it 'keeps a group nilable for a parameter whose default is a match' do
    expect(infer_last_line('md[1]', ', md = s.match(/(a)/)')).to eq('::String, nil')
  end

  it 'terminates on a variable reassigned from its own group' do
    expect(infer_last_line("md = s.match(/(a)/)\nmd = md[1].match(/(b)/)\nmd[1]")).to eq('::String, nil')
  end
end
