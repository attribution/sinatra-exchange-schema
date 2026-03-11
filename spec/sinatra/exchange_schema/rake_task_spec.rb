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

      endpoint :get, '/v2/items' do
        summary 'List items'
      end

      get('/v2/items') { 'ok' }
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
        expect(content['openapi']).to eq('3.0.0')
        expect(content['info']['title']).to eq('Test API')
        expect(content['info']['version']).to eq('2.0')
        expect(content['paths']).to have_key('/v2/items')
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
        expect(content['paths']).to have_key('/v2/items')
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

    it 'defaults to :environment prerequisite' do
      # Define a stub :environment task so Rake doesn't blow up
      Rake::Task.define_task(:environment)
      described_class.install(app: build_app_with_endpoints)

      task = Rake::Task['exchange_schema:openapi']
      expect(task.prerequisites).to include('environment')
    end
  end
end
