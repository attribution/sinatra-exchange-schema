require 'spec_helper'

describe Sinatra::ExchangeSchema do
  let(:test_app) do
    Class.new(Sinatra::Base) do
      register Sinatra::ExchangeSchema

      endpoint :post, '/test' do
        summary 'Test endpoint'
        body do
          string :name, required: true
          integer :count
        end
      end

      endpoint :get, '/test' do
        summary 'Test GET'
        query do
          string :status, enum: %w[active inactive]
        end
      end

      endpoint :post, '/test_with_response' do
        summary 'With response schema'
        body do
          string :name, required: true
        end
        response 200 do
          string :id, required: true
          string :name
        end
        response 400 do
          string :error, required: true
        end
      end

      endpoint :post, '/test_invalid_response' do
        summary 'Returns invalid response'
        body do
          string :name, required: true
        end
        response 200 do
          string :id, required: true
        end
      end

      endpoint :post, '/test_500_response' do
        summary 'Returns 500'
        body do
          string :name, required: true
        end
        response 200 do
          string :id, required: true
        end
      end

      endpoint :post, '/test_plain_response' do
        summary 'Returns plain text'
        body do
          string :name, required: true
        end
        response 200 do
          string :id, required: true
        end
      end

      post '/test' do
        [200, {}, 'ok']
      end

      get '/test' do
        [200, {}, 'ok']
      end

      post '/test_with_response' do
        content_type :json
        if request.path_info.include?('fail')
          status 400
          { error: 'bad request' }.to_json
        else
          { id: '123', name: 'hello' }.to_json
        end
      end

      post '/test_with_response/fail' do
        content_type :json
        status 400
        { error: 'bad request' }.to_json
      end

      post '/test_invalid_response' do
        content_type :json
        { name: 'no_id' }.to_json
      end

      post '/test_500_response' do
        content_type :json
        status 500
        { unexpected: true }.to_json
      end

      post '/test_plain_response' do
        'plain text response'
      end

      endpoint :post, '/test_array_response' do
        summary 'Array response'
        body do
          string :name, required: true
        end
        response 200 do
          string :id, required: true
          string :name
        end
      end

      endpoint :post, '/test_invalid_array_response' do
        summary 'Invalid array response'
        body do
          string :name, required: true
        end
        response 200 do
          string :id, required: true
        end
      end

      endpoint :post, '/test_empty_array_response' do
        summary 'Empty array response'
        body do
          string :name, required: true
        end
        response 200 do
          string :id, required: true
        end
      end

      post '/test_array_response' do
        content_type :json
        [{ id: '1', name: 'a' }, { id: '2', name: 'b' }].to_json
      end

      post '/test_invalid_array_response' do
        content_type :json
        [{ id: '1' }, { name: 'missing_id' }].to_json
      end

      post '/test_empty_array_response' do
        content_type :json
        [].to_json
      end

      endpoint :get, '/test_primitive_array' do
        summary 'Primitive array response'
        response 200, items: :string
      end

      endpoint :get, '/test_primitive_array_invalid' do
        summary 'Invalid primitive array response'
        response 200, items: :string
      end

      get '/test_primitive_array' do
        content_type :json
        %w[a b c].to_json
      end

      get '/test_primitive_array_invalid' do
        content_type :json
        [1, 2, 3].to_json
      end

      get '/no_schema' do
        'ok'
      end

      options '/no_schema' do
        'ok'
      end
    end
  end

  let(:app) { test_app.new }

  describe 'endpoint declarations' do
    it 'registers declarations' do
      declarations = test_app.endpoint_declarations
      expect(declarations.map(&:summary)).to include('Test endpoint', 'Test GET', 'With response schema')
    end

    it 'stores summary' do
      decl = test_app.endpoint_declarations.first
      expect(decl.summary).to eq('Test endpoint')
    end

    it 'builds body schema' do
      decl = test_app.endpoint_declarations.first
      expect(decl.body_schema['properties']).to have_key('name')
      expect(decl.body_schema['required']).to eq(['name'])
    end

    it 'builds query schema' do
      decl = test_app.endpoint_declarations.find { |d| d.summary == 'Test GET' }
      expect(decl.query_schema['properties']['status']['enum']).to eq(%w[active inactive])
    end

    it 'builds response schemas' do
      decl = test_app.endpoint_declarations.find { |d| d.summary == 'With response schema' }
      expect(decl.response_schemas.keys).to contain_exactly(200, 400)
      expect(decl.response_schemas[200]['properties']).to have_key('id')
      expect(decl.response_schemas[400]['required']).to eq(['error'])
    end
  end

  describe 'before filter validation' do
    include Rack::Test::Methods

    def app
      test_app
    end

    context 'with valid body' do
      it 'returns 200' do
        post '/test', { name: 'test', count: 1 }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
      end
    end

    context 'with invalid body' do
      it 'raises SchemaValidationError' do
        expect do
          post '/test', { count: 'not_a_number' }.to_json, 'CONTENT_TYPE' => 'application/json'
        end.to raise_error(Sinatra::ExchangeSchema::RequestValidator::SchemaValidationError,
                           /schema validation failed/i)
      end
    end

    context 'with invalid body and :warn mode' do
      around do |example|
        Sinatra::ExchangeSchema.request_validation = :warn
        example.run
      ensure
        Sinatra::ExchangeSchema.request_validation = :strict
      end

      it 'does not raise' do
        post '/test', { count: 'not_a_number' }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
      end
    end

    context 'with valid query params' do
      it 'returns 200' do
        get '/test', status: 'active'
        expect(last_response.status).to eq(200)
      end
    end

    context 'with invalid query params' do
      it 'raises SchemaValidationError' do
        expect do
          get '/test', status: 'unknown'
        end.to raise_error(Sinatra::ExchangeSchema::RequestValidator::SchemaValidationError,
                           /schema validation failed/i)
      end
    end

    context 'with empty body' do
      it 'returns 200 without validation' do
        post '/test', '', 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
      end
    end
  end

  describe 'after filter response validation' do
    include Rack::Test::Methods

    def app
      test_app
    end

    context 'with valid 200 response' do
      it 'returns without error' do
        post '/test_with_response', { name: 'hello' }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
      end
    end

    context 'with invalid response body' do
      it 'raises ResponseSchemaValidationError' do
        expect do
          post '/test_invalid_response', { name: 'hello' }.to_json, 'CONTENT_TYPE' => 'application/json'
        end.to raise_error(Sinatra::ExchangeSchema::ResponseValidator::ResponseSchemaValidationError,
                           /Response schema validation failed/i)
      end
    end

    context 'with invalid response and :warn mode' do
      around do |example|
        Sinatra::ExchangeSchema.response_validation = :warn
        example.run
      ensure
        Sinatra::ExchangeSchema.response_validation = :strict
      end

      it 'logs without raising' do
        post '/test_invalid_response', { name: 'hello' }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
      end
    end

    context 'with no response schema declared' do
      it 'passes through without validation' do
        post '/test', { name: 'hello' }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
      end
    end

    context 'with undeclared status code' do
      it 'skips validation' do
        post '/test_500_response', { name: 'hello' }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(500)
      end
    end

    context 'with non-JSON response' do
      it 'skips gracefully' do
        post '/test_plain_response', { name: 'hello' }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
      end
    end
  end

  describe 'array request body validation' do
    include Rack::Test::Methods

    def app
      test_app
    end

    context 'with valid array body' do
      it 'validates all elements' do
        post '/test', [{ name: 'a', count: 1 }, { name: 'b', count: 2 }].to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
      end
    end

    context 'with invalid element in array body' do
      it 'raises SchemaValidationError for the invalid element' do
        expect do
          post '/test', [{ name: 'valid' }, { count: 'not_a_number' }].to_json, 'CONTENT_TYPE' => 'application/json'
        end.to raise_error(Sinatra::ExchangeSchema::RequestValidator::SchemaValidationError)
      end
    end

    context 'with empty array body' do
      it 'passes without error' do
        post '/test', [].to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
      end
    end
  end

  describe 'array response body validation' do
    include Rack::Test::Methods

    def app
      test_app
    end

    context 'with valid array response' do
      it 'validates all elements' do
        post '/test_array_response', { name: 'hello' }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
      end
    end

    context 'with invalid element in array response' do
      it 'raises ResponseSchemaValidationError' do
        expect do
          post '/test_invalid_array_response', { name: 'hello' }.to_json, 'CONTENT_TYPE' => 'application/json'
        end.to raise_error(Sinatra::ExchangeSchema::ResponseValidator::ResponseSchemaValidationError)
      end
    end

    context 'with empty array response' do
      it 'passes without error' do
        post '/test_empty_array_response', { name: 'hello' }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
      end
    end
  end

  describe 'primitive type response validation' do
    include Rack::Test::Methods

    def app
      test_app
    end

    context 'with valid primitive array response' do
      it 'validates successfully' do
        get '/test_primitive_array'
        expect(last_response.status).to eq(200)
      end
    end

    context 'with invalid primitive array response' do
      it 'raises ResponseSchemaValidationError' do
        expect do
          get '/test_primitive_array_invalid'
        end.to raise_error(Sinatra::ExchangeSchema::ResponseValidator::ResponseSchemaValidationError)
      end
    end
  end

  describe 'endpoint_security propagation' do
    it 'applies controller-level endpoint_security to declarations' do
      app_class = Class.new(Sinatra::Base) do
        register Sinatra::ExchangeSchema
        set :endpoint_security, :bearer

        endpoint :get, '/secured' do
          summary 'Secured'
        end

        get('/secured') { 'ok' }
      end

      decl = app_class.endpoint_declarations.find { |d| d.summary == 'Secured' }
      expect(decl.security).to eq([{ 'bearer' => [] }])
    end

    it 'does not override explicit security :none' do
      app_class = Class.new(Sinatra::Base) do
        register Sinatra::ExchangeSchema
        set :endpoint_security, :bearer

        endpoint :get, '/public' do
          summary 'Public'
          security :none
        end

        get('/public') { 'ok' }
      end

      decl = app_class.endpoint_declarations.find { |d| d.summary == 'Public' }
      expect(decl.security).to eq([])
    end

    it 'leaves security nil when no controller default set' do
      decl = test_app.endpoint_declarations.find { |d| d.summary == 'Test endpoint' }
      expect(decl.security).to be_nil
    end
  end

  describe 'openapi_file propagation' do
    it 'applies controller-level openapi_file to declarations' do
      app_class = Class.new(Sinatra::Base) do
        register Sinatra::ExchangeSchema
        set :openapi_file, 'admin.yaml'

        endpoint :get, '/admin' do
          summary 'Admin endpoint'
        end

        get('/admin') { 'ok' }
      end

      decl = app_class.endpoint_declarations.find { |d| d.summary == 'Admin endpoint' }
      expect(decl.openapi_file).to eq('admin.yaml')
    end

    it 'endpoint-level openapi_file overrides controller-level' do
      app_class = Class.new(Sinatra::Base) do
        register Sinatra::ExchangeSchema
        set :openapi_file, 'admin.yaml'

        endpoint :get, '/special' do
          summary 'Special endpoint'
          openapi_file 'special.yaml'
        end

        get('/special') { 'ok' }
      end

      decl = app_class.endpoint_declarations.find { |d| d.summary == 'Special endpoint' }
      expect(decl.openapi_file).to eq('special.yaml')
    end

    it 'leaves openapi_file nil when no controller default set' do
      decl = test_app.endpoint_declarations.find { |d| d.summary == 'Test endpoint' }
      expect(decl.openapi_file).to be_nil
    end
  end

  describe 'missing endpoint schema detection' do
    include Rack::Test::Methods

    def app
      test_app
    end

    context 'with :warn mode' do
      around do |example|
        Sinatra::ExchangeSchema.missing_schema = :warn
        example.run
      ensure
        Sinatra::ExchangeSchema.missing_schema = :strict
      end

      it 'does not raise' do
        get '/no_schema'
        expect(last_response.status).to eq(200)
      end
    end

    context 'with :strict mode' do
      it 'raises MissingEndpointSchemaError' do
        expect { get '/no_schema' }.to raise_error(
          Sinatra::ExchangeSchema::MissingEndpointSchemaError,
          /No endpoint schema declared for GET \/no_schema/
        )
      end
    end

    context 'with :off mode' do
      around do |example|
        Sinatra::ExchangeSchema.missing_schema = :off
        example.run
      ensure
        Sinatra::ExchangeSchema.missing_schema = :strict
      end

      it 'does not warn or raise' do
        get '/no_schema'
        expect(last_response.status).to eq(200)
      end
    end

    context 'with OPTIONS request' do
      it 'does not warn or raise' do
        options '/no_schema'
        expect(last_response.status).to eq(200)
      end
    end
  end

  describe 'per-endpoint validation modes' do
    include Rack::Test::Methods

    context 'endpoint overrides controller and app-wide for request_validation' do
      let(:app_class) do
        Class.new(Sinatra::Base) do
          register Sinatra::ExchangeSchema

          endpoint :post, '/strict_endpoint' do
            summary 'Strict endpoint'
            request_validation :strict
            body do
              string :name, required: true
            end
          end

          endpoint :post, '/off_endpoint' do
            summary 'Off endpoint'
            request_validation :off
            body do
              string :name, required: true
            end
          end

          post('/strict_endpoint') { 'ok' }
          post('/off_endpoint') { 'ok' }
        end
      end

      def app
        app_class
      end

      around do |example|
        Sinatra::ExchangeSchema.request_validation = :warn
        example.run
      ensure
        Sinatra::ExchangeSchema.request_validation = :strict
      end

      it 'raises for :strict endpoint even when app-wide is :warn' do
        expect do
          post '/strict_endpoint', { count: 1 }.to_json, 'CONTENT_TYPE' => 'application/json'
        end.to raise_error(Sinatra::ExchangeSchema::RequestValidator::SchemaValidationError)
      end

      it 'skips validation for :off endpoint' do
        post '/off_endpoint', { count: 1 }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
      end
    end

    context 'endpoint overrides controller for response_validation' do
      let(:app_class) do
        Class.new(Sinatra::Base) do
          register Sinatra::ExchangeSchema
          set :response_validation, :warn

          endpoint :post, '/strict_response' do
            summary 'Strict response'
            response_validation :strict
            body do
              string :name, required: true
            end
            response 200 do
              string :id, required: true
            end
          end

          post '/strict_response' do
            content_type :json
            { name: 'no_id' }.to_json
          end
        end
      end

      def app
        app_class
      end

      around do |example|
        Sinatra::ExchangeSchema.response_validation = :warn
        example.run
      ensure
        Sinatra::ExchangeSchema.response_validation = :strict
      end

      it 'raises for :strict endpoint even when controller is :warn' do
        expect do
          post '/strict_response', { name: 'hello' }.to_json, 'CONTENT_TYPE' => 'application/json'
        end.to raise_error(Sinatra::ExchangeSchema::ResponseValidator::ResponseSchemaValidationError)
      end
    end
  end

  describe 'per-controller validation modes' do
    include Rack::Test::Methods

    context 'controller overrides app-wide' do
      let(:app_class) do
        Class.new(Sinatra::Base) do
          register Sinatra::ExchangeSchema
          set :request_validation, :off

          endpoint :post, '/controller_off' do
            summary 'Controller off'
            body do
              string :name, required: true
            end
          end

          post('/controller_off') { 'ok' }
        end
      end

      def app
        app_class
      end

      it 'uses controller setting over app-wide :strict' do
        post '/controller_off', { count: 1 }.to_json, 'CONTENT_TYPE' => 'application/json'
        expect(last_response.status).to eq(200)
      end
    end

    context 'controller sets :strict for missing_schema' do
      let(:app_class) do
        Class.new(Sinatra::Base) do
          register Sinatra::ExchangeSchema
          set :missing_schema, :strict

          get('/unregistered') { 'ok' }
        end
      end

      def app
        app_class
      end

      around do |example|
        Sinatra::ExchangeSchema.missing_schema = :off
        example.run
      ensure
        Sinatra::ExchangeSchema.missing_schema = :strict
      end

      it 'raises even when app-wide is :off' do
        expect { get '/unregistered' }.to raise_error(
          Sinatra::ExchangeSchema::MissingEndpointSchemaError
        )
      end
    end
  end

  describe 'on_exchange_schema_warning callback' do
    include Rack::Test::Methods

    context 'when defined on the controller' do
      let(:warnings) { [] }

      let(:app_class) do
        captured = warnings
        Class.new(Sinatra::Base) do
          register Sinatra::ExchangeSchema
          set :request_validation, :warn

          define_method(:on_exchange_schema_warning) do |type, message, context|
            captured << { type: type, message: message, context: context }
          end

          endpoint :post, '/callback_test' do
            summary 'Callback test'
            body do
              string :name, required: true
            end
          end

          post('/callback_test') { 'ok' }
        end
      end

      def app
        app_class
      end

      it 'receives type, message, and context' do
        post '/callback_test', { count: 1 }.to_json, 'CONTENT_TYPE' => 'application/json'

        expect(warnings.size).to eq(1)
        expect(warnings.first).to match(
          type: :request_validation,
          message: /schema validation failed/i,
          context: {
            method: 'POST',
            path: '/callback_test',
            errors: a_collection_including(a_hash_including(:field, :error, :type))
          }
        )
      end
    end

    context 'when not defined on the controller' do
      let(:app_class) do
        Class.new(Sinatra::Base) do
          register Sinatra::ExchangeSchema
          set :request_validation, :warn

          endpoint :post, '/no_callback' do
            summary 'No callback'
            body do
              string :name, required: true
            end
          end

          post('/no_callback') { 'ok' }
        end
      end

      def app
        app_class
      end

      it 'falls back to logger.warn' do
        fake_logger = instance_double(Logger, warn: nil)
        allow_any_instance_of(app_class).to receive(:logger).and_return(fake_logger)

        post '/no_callback', { count: 1 }.to_json, 'CONTENT_TYPE' => 'application/json'

        expect(fake_logger).to have_received(:warn).with(/schema validation failed/i)
      end
    end

    context 'with :strict mode and callback defined' do
      let(:warnings) { [] }

      let(:app_class) do
        captured = warnings
        Class.new(Sinatra::Base) do
          register Sinatra::ExchangeSchema
          set :request_validation, :strict

          define_method(:on_exchange_schema_warning) do |type, message, context|
            captured << { type: type, message: message, context: context }
          end

          endpoint :post, '/strict_callback' do
            summary 'Strict callback'
            body do
              string :name, required: true
            end
          end

          post('/strict_callback') { 'ok' }
        end
      end

      def app
        app_class
      end

      it 'calls callback AND raises' do
        expect do
          post '/strict_callback', { count: 1 }.to_json, 'CONTENT_TYPE' => 'application/json'
        end.to raise_error(Sinatra::ExchangeSchema::RequestValidator::SchemaValidationError)

        expect(warnings.size).to eq(1)
      end
    end

    context 'for missing_schema warnings' do
      let(:warnings) { [] }

      let(:app_class) do
        captured = warnings
        Class.new(Sinatra::Base) do
          register Sinatra::ExchangeSchema
          set :missing_schema, :warn

          define_method(:on_exchange_schema_warning) do |type, message, context|
            captured << { type: type, message: message, context: context }
          end

          get('/undeclared') { 'ok' }
        end
      end

      def app
        app_class
      end

      around do |example|
        Sinatra::ExchangeSchema.missing_schema = :off
        example.run
      ensure
        Sinatra::ExchangeSchema.missing_schema = :strict
      end

      it 'calls callback with :missing_schema type' do
        get '/undeclared'

        expect(warnings.size).to eq(1)
        expect(warnings.first).to match(
          type: :missing_schema,
          message: /No endpoint schema declared/,
          context: { method: 'GET', path: '/undeclared', errors: [] }
        )
      end
    end
  end

  describe 'mode validation' do
    it 'rejects invalid modes' do
      expect do
        Sinatra::ExchangeSchema.request_validation = :invalid
      end.to raise_error(ArgumentError, /Invalid mode/)
    end
  end
end
