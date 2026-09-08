# Installs the `exchange_schema:openapi` Rake task that generates an OpenAPI 3.1
# YAML spec from endpoint schema declarations, and `exchange_schema:data_types`
# that dumps declared data types for review. Require this file from
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

      # Defines the `exchange_schema:openapi` and `exchange_schema:data_types` Rake tasks.
      #
      # @param app [Class, Proc] Sinatra app class or a lambda that returns
      #   one (evaluated at task runtime so :environment can load it first).
      # @param info [Hash] OpenAPI info fields (:title, :version, :description).
      # @param output [String, nil] Output file path. Falls back to
      #   ENV['OUTPUT'] then './openapi.yaml'.
      # @param depends_on Prerequisites for the task (default: :environment).
      def self.install(app:, info: {}, output: nil, depends_on: :environment)
        namespace :exchange_schema do
          desc 'Generate OpenAPI 3.1 YAML from endpoint schema declarations'
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

          desc 'Dump declared data types beside scopes and response properties (DISTINCT=1 for the token vocabulary)'
          task data_types: depends_on do
            require 'sinatra/exchange_schema'

            app_class = app.is_a?(Proc) ? app.call : app
            declarations = app_class.endpoint_declarations
            puts ENV['DISTINCT'] ? data_types_vocabulary(declarations) : data_types_table(declarations)
          end
        end
      end

      # One aligned row per declaration: endpoint, scopes, data types and the
      # top-level properties of its first 2xx response schema.
      def self.data_types_table(declarations)
        header = %w[ENDPOINT SCOPES DATA_TYPES RESPONSE]
        rows = declarations.sort_by { |d| [d.path, d.http_method] }.map do |d|
          ["#{d.http_method} #{d.path}", d.scopes.join(', '), format_data_types(d.data_types), format_response(d)]
        end
        widths = ([header] + rows).transpose.map { |column| column.map(&:length).max }
        ([header] + rows).map do |row|
          row.zip(widths).map { |cell, width| cell.ljust(width) }.join(' | ').rstrip
        end.join("\n")
      end

      # Distinct data type tokens with the number of declarations using each.
      def self.data_types_vocabulary(declarations)
        counts = declarations.flat_map { |d| d.data_types || [] }.tally
        width = counts.keys.map(&:length).max || 0
        counts.sort_by { |token, count| [-count, token] }.map do |token, count|
          "#{token.ljust(width)}  #{count}"
        end.join("\n")
      end

      def self.format_data_types(data_types)
        return '-' if data_types.nil?
        return 'none' if data_types.empty?

        data_types.join(', ')
      end

      def self.format_response(declaration)
        schema = declaration.response_schemas.find { |status, _| status.between?(200, 299) }&.last
        return '-' unless schema

        if Array(schema['type']).include?('array')
          items = schema['items'] || {}
          names = items['properties'] ? items['properties'].keys : [items['type']].compact
          "[#{names.join(', ')}]"
        else
          names = (schema['properties'] || {}).keys
          names.empty? ? '-' : names.join(', ')
        end
      end
    end
  end
end
