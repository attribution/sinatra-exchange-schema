require 'spec_helper'

describe Sinatra::ExchangeSchema::EndpointDeclaration do
  describe '#path_regex' do
    it 'matches a simple path exactly' do
      decl = described_class.new(:get, '/v2/filters')
      expect(decl.path_regex).to match('/v2/filters')
      expect(decl.path_regex).not_to match('/v2/filters/extra')
      expect(decl.path_regex).not_to match('/v2')
    end

    it 'captures path params' do
      decl = described_class.new(:get, '/v2/filters/:filter_id')
      match = decl.path_regex.match('/v2/filters/42')
      expect(match).not_to be_nil
      expect(match[:filter_id]).to eq('42')
    end

    it 'escapes dots in static segments' do
      decl = described_class.new(:get, '/v2/data.json')
      expect(decl.path_regex).to match('/v2/data.json')
      expect(decl.path_regex).not_to match('/v2/dataXjson')
    end

    it 'escapes other metacharacters' do
      decl = described_class.new(:get, '/v2/(special)')
      expect(decl.path_regex).to match('/v2/(special)')
      expect(decl.path_regex).not_to match('/v2/special')
    end

    it 'handles multiple params' do
      decl = described_class.new(:get, '/v2/projects/:project_id/filters/:filter_id')
      match = decl.path_regex.match('/v2/projects/7/filters/42')
      expect(match).not_to be_nil
      expect(match[:project_id]).to eq('7')
      expect(match[:filter_id]).to eq('42')
    end
  end

  describe '#response with items: kwarg' do
    it 'stores a string type schema' do
      decl = described_class.new(:get, '/test')
      decl.response(200, items: :string)
      expect(decl.response_schemas[200]).to eq({ 'type' => 'string' })
    end

    it 'stores an array type schema' do
      decl = described_class.new(:get, '/test')
      decl.response(200, items: :array)
      expect(decl.response_schemas[200]).to eq({ 'type' => 'array' })
    end

    it 'stores an integer type schema' do
      decl = described_class.new(:get, '/test')
      decl.response(200, items: :integer)
      expect(decl.response_schemas[200]).to eq({ 'type' => 'integer' })
    end
  end

  describe '#security' do
    it 'sets bearer security' do
      decl = described_class.new(:get, '/test')
      decl.security(:bearer)
      expect(decl.security).to eq([{ 'bearer' => [] }])
    end

    it 'sets basic security' do
      decl = described_class.new(:get, '/test')
      decl.security(:basic)
      expect(decl.security).to eq([{ 'basic' => [] }])
    end

    it 'sets none security' do
      decl = described_class.new(:get, '/test')
      decl.security(:none)
      expect(decl.security).to eq([])
    end

    it 'raises for unknown auth scheme' do
      decl = described_class.new(:get, '/test')
      expect { decl.security(:unknown) }.to raise_error(ArgumentError, /Unknown auth: unknown/)
    end
  end

  describe '#matches?' do
    it 'checks both method and path' do
      decl = described_class.new(:post, '/v2/filters')
      expect(decl.matches?('POST', '/v2/filters')).to be true
      expect(decl.matches?('GET', '/v2/filters')).to be false
      expect(decl.matches?('POST', '/v2/other')).to be false
    end
  end
end
