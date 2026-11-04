# frozen_string_literal: true

describe Solargraph::Parser::RegexpGroups do
  {
    '/(a)(b)/' => [1, 2],
    '/(a)?(b)*(c){0,2}(d){,2}(e){0}/' => [],
    '/(a)+(b){2}(c){1,}/' => [1, 2, 3],
    '/((a)|b)(c)/' => [1, 3],
    '/(a)|(b)/' => [],
    '/(?:(a))(?i:(b))(?>(c))(?m)(d)/' => [1, 2, 3, 4],
    '/[(][[:alpha:]](a)\(\)/' => [1],
    '/\u{0}(a)/' => [1],
    '//' => [],
    '/(a)/x' => [],
    '%r{(a)}' => [],
    '/(?<n>a)/' => [],
    '/(?x)(a)/' => [],
    '/(a)\g<1>/' => [],
    "/(a)\#{s}/" => []
  }.each do |literal, required|
    it "finds groups #{required} in #{literal}" do
      expect(described_class.new(Solargraph::Parser.parse(literal)).required).to eq(required)
    end
  end
end
