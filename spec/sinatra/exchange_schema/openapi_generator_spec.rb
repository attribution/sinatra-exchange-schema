require 'spec_helper'

describe Sinatra::ExchangeSchema::OpenapiGenerator do
  def build_declaration(http_method, path, summary: nil, &block)
    decl = Sinatra::ExchangeSchema::EndpointDeclaration.new(http_method, path)
    decl.summary(summary) if summary
    decl.instance_eval(&block) if block
    decl
  end

  describe '.call' do
    it 'returns top-level OpenAPI keys' do
      doc = described_class.call([], info: { title: 'Test', version: '1.0', description: 'desc' })

      expect(doc['openapi']).to eq('3.0.0')
      expect(doc['info']['title']).to eq('Test')
      expect(doc['info']['version']).to eq('1.0')
      expect(doc['info']['description']).to eq('desc')
      expect(doc['paths']).to eq({})
    end

    it 'converts GET with query params' do
      decl = build_declaration(:get, '/v2/items', summary: 'List items') do
        query do
          string :status, enum: %w[active archived], required: true
          integer :page
        end
      end

      doc = described_class.call([decl])
      op = doc['paths']['/v2/items']['get']

      expect(op['summary']).to eq('List items')
      expect(op['parameters'].size).to eq(2)

      status_param = op['parameters'].find { |p| p['name'] == 'status' }
      expect(status_param['in']).to eq('query')
      expect(status_param['required']).to eq(true)
      expect(status_param['schema']['enum']).to eq(%w[active archived])

      page_param = op['parameters'].find { |p| p['name'] == 'page' }
      expect(page_param['in']).to eq('query')
      expect(page_param).not_to have_key('required')
    end

    it 'converts POST with body schema' do
      decl = build_declaration(:post, '/v2/items', summary: 'Create item') do
        body do
          string :name, required: true
          integer :quantity
        end
      end

      doc = described_class.call([decl])
      op = doc['paths']['/v2/items']['post']

      expect(op['requestBody']['content']['application/json']['schema']).to eq(decl.body_schema)
    end

    it 'extracts path params and converts Sinatra paths' do
      decl = build_declaration(:get, '/v2/filters/:filter_id', summary: 'Get filter')

      doc = described_class.call([decl])

      expect(doc['paths']).to have_key('/v2/filters/{filter_id}')
      op = doc['paths']['/v2/filters/{filter_id}']['get']

      path_param = op['parameters'].find { |p| p['name'] == 'filter_id' }
      expect(path_param['in']).to eq('path')
      expect(path_param['required']).to eq(true)
      expect(path_param['schema']['type']).to eq('integer')
    end

    it 'infers string type for path params not ending in _id' do
      decl = build_declaration(:get, '/v2/items/:slug', summary: 'Get by slug')

      doc = described_class.call([decl])
      op = doc['paths']['/v2/items/{slug}']['get']

      slug_param = op['parameters'].find { |p| p['name'] == 'slug' }
      expect(slug_param['schema']['type']).to eq('string')
    end

    it 'maps response schemas with status codes' do
      decl = build_declaration(:post, '/v2/items', summary: 'Create') do
        response 200 do
          string :id, required: true
        end
        response 400 do
          string :error, required: true
        end
      end

      doc = described_class.call([decl])
      responses = doc['paths']['/v2/items']['post']['responses']

      expect(responses).to have_key('200')
      expect(responses['200']['description']).to eq('OK')
      expect(responses['200']['content']['application/json']['schema']).to eq(decl.response_schemas[200])

      expect(responses).to have_key('400')
      expect(responses['400']['description']).to eq('Bad Request')
    end

    it 'returns default 200 response for endpoints without response schemas' do
      decl = build_declaration(:get, '/v2/ping', summary: 'Ping')

      doc = described_class.call([decl])
      responses = doc['paths']['/v2/ping']['get']['responses']

      expect(responses).to eq({ '200' => { 'description' => 'OK' } })
    end

    it 'merges multiple methods on the same path' do
      get_decl = build_declaration(:get, '/v2/filters/:filter_id', summary: 'Get filter')
      delete_decl = build_declaration(:delete, '/v2/filters/:filter_id', summary: 'Delete filter')

      doc = described_class.call([get_decl, delete_decl])
      path_item = doc['paths']['/v2/filters/{filter_id}']

      expect(path_item).to have_key('get')
      expect(path_item).to have_key('delete')
      expect(path_item['get']['summary']).to eq('Get filter')
      expect(path_item['delete']['summary']).to eq('Delete filter')
    end

    it 'derives security and securitySchemes from declarations' do
      decl = build_declaration(:get, '/v2/items', summary: 'List') do
        security :bearer
      end

      doc = described_class.call([decl])
      expect(doc['security']).to eq([{ 'bearer' => [] }])
      expect(doc['components']['securitySchemes']['bearer']).to eq(
        { 'type' => 'http', 'scheme' => 'bearer' }
      )
    end

    it 'derives security and securitySchemes from basic auth declarations' do
      decl = build_declaration(:get, '/v2/stats', summary: 'Stats') do
        security :basic
      end

      doc = described_class.call([decl])
      expect(doc['security']).to eq([{ 'basic' => [] }])
      expect(doc['components']['securitySchemes']['basic']).to eq(
        { 'type' => 'http', 'scheme' => 'basic' }
      )
    end

    it 'includes per-operation security when mixed auth schemes are used' do
      bearer_decl = build_declaration(:get, '/v2/items', summary: 'List') do
        security :bearer
      end
      basic_decl = build_declaration(:get, '/v2/stats', summary: 'Stats') do
        security :basic
      end

      doc = described_class.call([bearer_decl, basic_decl])
      expect(doc['components']['securitySchemes']).to have_key('bearer')
      expect(doc['components']['securitySchemes']).to have_key('basic')

      # Per-operation security should be present since each differs from top-level
      bearer_op = doc['paths']['/v2/items']['get']
      basic_op = doc['paths']['/v2/stats']['get']
      expect(bearer_op['security']).to eq([{ 'bearer' => [] }])
      expect(basic_op['security']).to eq([{ 'basic' => [] }])
    end

    it 'omits security when no declarations have security' do
      doc = described_class.call([])
      expect(doc).not_to have_key('security')
      expect(doc).not_to have_key('components')
    end

    it 'omits per-operation security when it matches top-level default' do
      decl = build_declaration(:get, '/v2/items', summary: 'List') do
        security :bearer
      end

      doc = described_class.call([decl])
      op = doc['paths']['/v2/items']['get']
      expect(op).not_to have_key('security')
    end

    it 'includes per-operation security override for :none' do
      secured = build_declaration(:get, '/v2/items', summary: 'List') do
        security :bearer
      end
      public_decl = build_declaration(:get, '/v2/public', summary: 'Public') do
        security :none
      end

      doc = described_class.call([secured, public_decl])
      op = doc['paths']['/v2/public']['get']
      expect(op['security']).to eq([])
    end
  end
end
