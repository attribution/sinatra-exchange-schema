require 'spec_helper'

# A named schema, declared once on the app and referenced from several endpoints: the document
# carries it once, and the filters validate through the reference.
describe 'named schemas' do
  include Rack::Test::Methods

  before do
    Sinatra::ExchangeSchema::Schemas.clear
  end

  after do
    Sinatra::ExchangeSchema::Schemas.clear
  end

  def app
    @app ||= Class.new(Sinatra::Base) do
      register Sinatra::ExchangeSchema
      set :raise_errors, true
      set :show_exceptions, false

      schema :Article do
        integer :id, required: true
        string :name, required: true
      end

      endpoint :post, '/articles' do
        body ref: :Article do
          string :note
        end
        response 200, ref: :Article
      end

      post '/articles' do
        content_type :json
        payload = JSON.parse(request.body.read)
        { id: payload['id'], name: payload['name'] }.to_json
      end

      endpoint :get, '/articles' do
        response 200, items: ref(:Article)
      end

      get '/articles' do
        content_type :json
        [{ id: 1, name: 'One' }, { id: 2, name: 'Two' }].to_json
      end
    end
  end

  let(:declarations) { app.endpoint_declarations }

  it 'validates a body through the reference, with the endpoint\'s own fields beside it' do
    post '/articles', { id: 1, name: 'One', note: 'first' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eq 200
  end

  it 'rejects what neither the named schema nor the endpoint declared' do
    expect { post '/articles', { id: 1, name: 'One', nope: true }.to_json, 'CONTENT_TYPE' => 'application/json' }
      .to raise_error(Sinatra::ExchangeSchema::RequestValidator::SchemaValidationError, %r{/})
  end

  it 'rejects a body the named schema requires more of' do
    expect { post '/articles', { id: 1, note: 'no name' }.to_json, 'CONTENT_TYPE' => 'application/json' }
      .to raise_error(Sinatra::ExchangeSchema::RequestValidator::SchemaValidationError, /name/)
  end

  it 'validates a response through the reference, alone and as array items' do
    post '/articles', { id: 1, name: 'One' }.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eq 200
    get '/articles'
    expect(last_response.status).to eq 200
  end

  it 'carries the named schema once in the document and points at it' do
    doc = Sinatra::ExchangeSchema::OpenapiGenerator.call(declarations)

    expect(doc.dig('components', 'schemas').keys).to eq ['Article']
    expect(doc.dig('components', 'schemas', 'Article', 'required')).to eq %w[id name]
    body = doc.dig('paths', '/articles', 'post', 'requestBody', 'content', 'application/json', 'schema')
    expect(body['allOf'].first).to eq('$ref' => '#/components/schemas/Article')
    expect(body['allOf'].last['properties'].keys).to eq ['note']
    expect(body['unevaluatedProperties']).to be false
    expect(doc.dig('paths', '/articles', 'post', 'responses', '200', 'content', 'application/json', 'schema')).to eq('$ref' => '#/components/schemas/Article')
    expect(doc.dig('paths', '/articles', 'get', 'responses', '200', 'content', 'application/json', 'schema', 'items')).to eq('$ref' => '#/components/schemas/Article')
  end
end
