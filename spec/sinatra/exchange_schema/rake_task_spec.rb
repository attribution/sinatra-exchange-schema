require 'spec_helper'
require 'sinatra/exchange_schema/rake_task'
require 'tmpdir'

describe Sinatra::ExchangeSchema::RakeTask do
  before do
    Rake::Task.clear
  end

  def build_app_with_endpoints
    Class.new(Sinatra::Base) do
      register Sinatra::ExchangeSchema

      endpoint :get, '/items' do
        summary 'List items'
      end

      get('/items') { 'ok' }
    end
  end

  def build_app_with_data_types
    Class.new(Sinatra::Base) do
      register Sinatra::ExchangeSchema

      endpoint :get, '/users/:id' do
        summary 'Show user'
        security :bearer, scopes: ['users:read']
        data_types :email, :postal_address
        response 200 do
          integer :id, required: true
          string :email
        end
      end

      endpoint :get, '/health' do
        summary 'Health check'
        security :none
        data_types :none
      end

      endpoint :get, '/emails' do
        summary 'List subscriber emails'
        data_types :email
        response 200, items: :string
      end

      endpoint :get, '/items' do
        summary 'List items'
        response 200, items: :object do
          integer :id
        end
      end

      get('/users/:id') { 'ok' }
      get('/health') { 'ok' }
      get('/emails') { 'ok' }
      get('/items') { 'ok' }
    end
  end

  describe '.install' do
    it 'defines an exchange_schema:openapi task' do
      described_class.install(app: build_app_with_endpoints, depends_on: [])

      expect(Rake::Task.task_defined?('exchange_schema:openapi')).to be true
    end

    it 'writes a valid YAML file with correct OpenAPI structure' do
      app = build_app_with_endpoints

      Dir.mktmpdir do |dir|
        output_path = File.join(dir, 'openapi.yaml')
        described_class.install(
          app: app,
          info: { title: 'Test API', version: '2.0' },
          output: output_path,
          depends_on: []
        )

        expect { Rake::Task['exchange_schema:openapi'].invoke }.to output(/Wrote OpenAPI spec/).to_stdout

        content = YAML.safe_load(File.read(output_path))
        expect(content['openapi']).to eq('3.1.0')
        expect(content['info']['title']).to eq('Test API')
        expect(content['info']['version']).to eq('2.0')
        expect(content['paths']).to have_key('/items')
      end
    end

    it 'accepts a lambda for app (evaluated at task runtime)' do
      app = build_app_with_endpoints
      called = false

      Dir.mktmpdir do |dir|
        output_path = File.join(dir, 'openapi.yaml')
        described_class.install(
          app: -> { called = true; app },
          output: output_path,
          depends_on: []
        )

        expect(called).to be false
        expect { Rake::Task['exchange_schema:openapi'].invoke }.to output(/Wrote OpenAPI spec/).to_stdout
        expect(called).to be true

        content = YAML.safe_load(File.read(output_path))
        expect(content['paths']).to have_key('/items')
      end
    end

    it 'respects custom output path' do
      Dir.mktmpdir do |dir|
        custom_path = File.join(dir, 'custom', 'spec.yaml')
        FileUtils.mkdir_p(File.dirname(custom_path))

        described_class.install(
          app: build_app_with_endpoints,
          output: custom_path,
          depends_on: []
        )

        expect { Rake::Task['exchange_schema:openapi'].invoke }.to output(/#{Regexp.escape(custom_path)}/).to_stdout
        expect(File.exist?(custom_path)).to be true
      end
    end

    it 'skips :environment prerequisite with depends_on: []' do
      described_class.install(app: build_app_with_endpoints, depends_on: [])

      task = Rake::Task['exchange_schema:openapi']
      expect(task.prerequisites).to be_empty
    end

    it 'splits endpoints into multiple files based on openapi_file' do
      app = Class.new(Sinatra::Base) do
        register Sinatra::ExchangeSchema

        endpoint :get, '/items' do
          summary 'List items'
        end

        endpoint :get, '/admin/users' do
          summary 'List users'
          openapi_file 'admin.yaml'
        end

        get('/items') { 'ok' }
        get('/admin/users') { 'ok' }
      end

      Dir.mktmpdir do |dir|
        output_path = File.join(dir, 'openapi.yaml')
        described_class.install(
          app: app,
          info: { title: 'Test API', version: '1.0' },
          output: output_path,
          depends_on: []
        )

        expect { Rake::Task['exchange_schema:openapi'].invoke }.to output(/Wrote OpenAPI spec/).to_stdout

        default_content = YAML.safe_load(File.read(output_path))
        expect(default_content['paths']).to have_key('/items')
        expect(default_content['paths']).not_to have_key('/admin/users')

        admin_content = YAML.safe_load(File.read(File.join(dir, 'admin.yaml')))
        expect(admin_content['paths']).to have_key('/admin/users')
        expect(admin_content['paths']).not_to have_key('/items')
      end
    end

    it 'writes all endpoints to default file when no openapi_file set' do
      Dir.mktmpdir do |dir|
        output_path = File.join(dir, 'openapi.yaml')
        described_class.install(
          app: build_app_with_endpoints,
          info: { title: 'Test API', version: '1.0' },
          output: output_path,
          depends_on: []
        )

        expect { Rake::Task['exchange_schema:openapi'].invoke }.to output(/1 endpoints/).to_stdout

        content = YAML.safe_load(File.read(output_path))
        expect(content['paths']).to have_key('/items')
      end
    end

    it 'groups endpoints by controller-level openapi_file' do
      app = Class.new(Sinatra::Base) do
        register Sinatra::ExchangeSchema
        set :openapi_file, 'admin.yaml'

        endpoint :get, '/admin/users' do
          summary 'List users'
        end

        endpoint :get, '/admin/roles' do
          summary 'List roles'
        end

        get('/admin/users') { 'ok' }
        get('/admin/roles') { 'ok' }
      end

      Dir.mktmpdir do |dir|
        output_path = File.join(dir, 'openapi.yaml')
        described_class.install(
          app: app,
          info: { title: 'Admin API', version: '1.0' },
          output: output_path,
          depends_on: []
        )

        expect { Rake::Task['exchange_schema:openapi'].invoke }.to output(/admin\.yaml.*2 endpoints/).to_stdout

        expect(File.exist?(output_path)).to be false
        admin_content = YAML.safe_load(File.read(File.join(dir, 'admin.yaml')))
        expect(admin_content['paths'].keys).to contain_exactly('/admin/users', '/admin/roles')
      end
    end

    it 'excludes endpoints with openapi_file false from all output files' do
      app = Class.new(Sinatra::Base) do
        register Sinatra::ExchangeSchema

        endpoint :get, '/items' do
          summary 'List items'
        end

        endpoint :get, '/robots.txt' do
          summary 'Robots exclusion'
          openapi_file false
        end

        get('/items') { 'ok' }
        get('/robots.txt') { 'ok' }
      end

      Dir.mktmpdir do |dir|
        output_path = File.join(dir, 'openapi.yaml')
        described_class.install(app: app, output: output_path, depends_on: [])

        expect { Rake::Task['exchange_schema:openapi'].invoke }.to output(/Wrote OpenAPI spec/).to_stdout

        content = YAML.safe_load(File.read(output_path))
        expect(content['paths']).to have_key('/items')
        expect(content['paths']).not_to have_key('/robots.txt')
      end
    end

    it 'defines an exchange_schema:data_types task' do
      described_class.install(app: build_app_with_endpoints, depends_on: [])

      expect(Rake::Task.task_defined?('exchange_schema:data_types')).to be true
    end

    it 'dumps endpoints with scopes, data types and response properties side by side' do
      described_class.install(app: build_app_with_data_types, depends_on: [])

      expect { Rake::Task['exchange_schema:data_types'].invoke }.to output(<<~TABLE).to_stdout
        ENDPOINT       | SCOPES     | DATA_TYPES            | RESPONSE
        GET /emails    |            | email                 | [string]
        GET /health    |            | none                  | -
        GET /items     |            | -                     | [id]
        GET /users/:id | users:read | email, postal_address | id, email
      TABLE
    end

    it 'dumps the distinct data type vocabulary with DISTINCT=1' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('DISTINCT').and_return('1')
      described_class.install(app: build_app_with_data_types, depends_on: [])

      expect { Rake::Task['exchange_schema:data_types'].invoke }.to output(<<~VOCABULARY).to_stdout
        email           2
        postal_address  1
      VOCABULARY
    end

    it 'defaults to :environment prerequisite' do
      # Define a stub :environment task so Rake doesn't blow up
      Rake::Task.define_task(:environment)
      described_class.install(app: build_app_with_endpoints)

      task = Rake::Task['exchange_schema:openapi']
      expect(task.prerequisites).to include('environment')
    end
  end
end
