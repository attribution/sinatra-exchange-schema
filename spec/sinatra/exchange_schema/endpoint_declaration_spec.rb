require 'spec_helper'

describe Sinatra::ExchangeSchema::EndpointDeclaration do
  describe '#path_regex' do
    it 'matches a simple path exactly' do
      decl = described_class.new(:get, '/articles')
      expect(decl.path_regex).to match('/articles')
      expect(decl.path_regex).not_to match('/articles/extra')
      expect(decl.path_regex).not_to match('/')
    end

    it 'captures path params' do
      decl = described_class.new(:get, '/articles/:id')
      match = decl.path_regex.match('/articles/42')
      expect(match).not_to be_nil
      expect(match[:id]).to eq('42')
    end

    it 'escapes dots in static segments' do
      decl = described_class.new(:get, '/data.json')
      expect(decl.path_regex).to match('/data.json')
      expect(decl.path_regex).not_to match('/dataXjson')
    end

    it 'escapes other metacharacters' do
      decl = described_class.new(:get, '/(special)')
      expect(decl.path_regex).to match('/(special)')
      expect(decl.path_regex).not_to match('/special')
    end

    it 'handles multiple params' do
      decl = described_class.new(:get, '/projects/:project_id/articles/:id')
      match = decl.path_regex.match('/projects/7/articles/42')
      expect(match).not_to be_nil
      expect(match[:project_id]).to eq('7')
      expect(match[:id]).to eq('42')
    end
  end

  describe '#close_body!' do
    it 'closes the top level' do
      decl = described_class.new(:post, '/articles')
      decl.body { string :name, required: true }
      decl.close_body!
      expect(decl.body_schema).to eq({
        'type'                 => 'object',
        'properties'           => { 'name' => { 'type' => 'string' } },
        'required'             => ['name'],
        'additionalProperties' => false
      })
    end

    it 'leaves nested objects open' do
      decl = described_class.new(:post, '/articles')
      decl.body do
        object :settings
        object :meta do
          string :source
        end
      end
      decl.close_body!
      expect(decl.body_schema['properties']['settings']).to eq({ 'type' => 'object' })
      expect(decl.body_schema['properties']['meta']).not_to have_key('additionalProperties')
    end

    it 'leaves the query schema alone' do
      decl = described_class.new(:get, '/articles')
      decl.query { string :status }
      decl.close_body!
      expect(decl.query_schema).not_to have_key('additionalProperties')
    end

    it 'does nothing when no body is declared' do
      decl = described_class.new(:get, '/articles')
      expect { decl.close_body! }.not_to raise_error
      expect(decl.body_schema).to be_nil
    end
  end

  describe '#additional_properties' do
    it 'defaults to nil so the controller or app decides' do
      decl = described_class.new(:post, '/articles')
      expect(decl.additional_properties).to be_nil
    end

    it 'stores an explicit opt-out' do
      decl = described_class.new(:post, '/articles')
      decl.additional_properties true
      expect(decl.additional_properties).to be true
    end
  end

  describe '#response with items: kwarg' do
    it 'wraps string element type in an array schema' do
      decl = described_class.new(:get, '/test')
      decl.response(200, items: :string)
      expect(decl.response_schemas[200]).to eq({ 'type' => 'array', 'items' => { 'type' => 'string' } })
    end

    it 'wraps array element type in an array schema' do
      decl = described_class.new(:get, '/test')
      decl.response(200, items: :array)
      expect(decl.response_schemas[200]).to eq({ 'type' => 'array', 'items' => { 'type' => 'array' } })
    end

    it 'wraps integer element type in an array schema' do
      decl = described_class.new(:get, '/test')
      decl.response(200, items: :integer)
      expect(decl.response_schemas[200]).to eq({ 'type' => 'array', 'items' => { 'type' => 'integer' } })
    end

    it 'wraps object element schema from block in an array schema' do
      decl = described_class.new(:get, '/test')
      decl.response(200, items: :object) do
        string :id, required: true
        string :token
      end
      expect(decl.response_schemas[200]).to eq({
        'type' => 'array',
        'items' => {
          'type' => 'object',
          'properties' => {
            'id'    => { 'type' => 'string' },
            'token' => { 'type' => 'string' }
          },
          'required' => ['id']
        }
      })
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

    it 'embeds scopes inside the security array' do
      decl = described_class.new(:get, '/test')
      decl.security(:bearer, scopes: ['articles:read'])
      expect(decl.security).to eq [{ 'bearer' => ['articles:read'] }]
    end

    it 'embeds multiple scopes' do
      decl = described_class.new(:get, '/test')
      decl.security(:bearer, scopes: ['analytics:read', 'users:read'])
      expect(decl.security).to eq [{ 'bearer' => ['analytics:read', 'users:read'] }]
    end

    it 'defaults to empty scopes when none given' do
      decl = described_class.new(:get, '/test')
      decl.security(:bearer)
      expect(decl.security).to eq [{ 'bearer' => [] }]
    end
  end

  describe '#scopes' do
    it 'returns [] when security is not set' do
      decl = described_class.new(:get, '/test')
      expect(decl.scopes).to eq []
    end

    it 'returns declared scopes' do
      decl = described_class.new(:get, '/test')
      decl.security(:bearer, scopes: ['articles:read'])
      expect(decl.scopes).to eq ['articles:read']
    end
  end

  describe '#openapi_file' do
    it 'defaults to nil' do
      decl = described_class.new(:get, '/test')
      expect(decl.openapi_file).to be_nil
    end

    it 'stores the value' do
      decl = described_class.new(:get, '/test')
      decl.openapi_file('admin.yaml')
      expect(decl.openapi_file).to eq('admin.yaml')
    end
  end

  describe '#matches?' do
    it 'checks both method and path' do
      decl = described_class.new(:post, '/articles')
      expect(decl.matches?('POST', '/articles')).to be true
      expect(decl.matches?('GET', '/articles')).to be false
      expect(decl.matches?('POST', '/other')).to be false
    end
  end
end
