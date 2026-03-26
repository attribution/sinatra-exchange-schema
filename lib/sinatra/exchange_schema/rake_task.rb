# Installs an `exchange_schema:openapi` Rake task that generates an OpenAPI 3.0
# YAML spec from endpoint schema declarations. Require this file from
# your Rakefile (it is NOT auto-required by the gem).
#
# Usage:
#
#   require 'sinatra/exchange_schema/rake_task'
#
#   Sinatra::ExchangeSchema::RakeTask.install(
#     app: -> { MyApp::Controllers::Base },
#     info: { title: 'My API', version: 'v1' }
#   )
require 'rake'
require 'yaml'

module Sinatra
  module ExchangeSchema
    class RakeTask
      extend Rake::DSL

      # Defines an `exchange_schema:openapi` Rake task.
      #
      # @param app [Class, Proc] Sinatra app class or a lambda that returns
      #   one (evaluated at task runtime so :environment can load it first).
      # @param info [Hash] OpenAPI info fields (:title, :version, :description).
      # @param output [String, nil] Output file path. Falls back to
      #   ENV['OUTPUT'] then './openapi.yaml'.
      # @param depends_on Prerequisites for the task (default: :environment).
      def self.install(app:, info: {}, output: nil, depends_on: :environment)
        namespace :exchange_schema do
          desc 'Generate OpenAPI 3.0 YAML from endpoint schema declarations'
          task openapi: depends_on do
            require 'sinatra/exchange_schema'

            app_class = app.is_a?(Proc) ? app.call : app
            declarations = app_class.endpoint_declarations
            output_path = output || ENV.fetch('OUTPUT', './openapi.yaml')
            output_dir = File.dirname(output_path)
            default_file = File.basename(output_path)

            # Group declarations by target file. Endpoints without an explicit
            # openapi_file fall back to the default output filename.
            # openapi_file false excludes the endpoint from all output files.
            groups = declarations
              .reject { |d| d.openapi_file == false }
              .group_by { |d| d.openapi_file || default_file }

            groups.each do |filename, group_decls|
              doc = OpenapiGenerator.call(group_decls, info: info)
              file_path = File.join(output_dir, filename)
              yaml = YAML.dump(doc).delete_prefix("---\n")
              File.write(file_path, yaml)
              puts "Wrote OpenAPI spec to #{file_path} (#{group_decls.size} endpoints)"
            end
          end
        end
      end
    end
  end
end
