# Generates an OpenAPI 3.0.0 specification hash from EndpointDeclaration objects.
# Converts the internal endpoint schema DSL into a standard OpenAPI document
# that can be serialized to YAML or JSON.
require 'rack/utils'

module Sinatra
  module ExchangeSchema
    class OpenapiGenerator
      def self.call(declarations, info: {})
        scheme_names = declarations
          .flat_map { |d| d.security || [] }
          .flat_map(&:keys).uniq

        paths = {}
        declarations.each do |decl|
          path_key = convert_path(decl.path)
          method_key = decl.http_method.downcase

          operation = build_operation(decl, scheme_names)

          paths[path_key] ||= {}
          paths[path_key][method_key] = operation
        end

        doc = {
          'openapi' => '3.0.0',
          'info' => {
            'title' => info[:title] || 'API',
            'version' => info[:version] || '1.0.0',
            'description' => info[:description] || ''
          },
          'paths' => paths
        }

        if scheme_names.any?
          doc['security'] = scheme_names.map { |n| { n => [] } }
          doc['components'] = {
            'securitySchemes' => EndpointDeclaration::AUTH_SCHEMES.slice(*scheme_names)
          }
        end

        doc
      end

      class << self
        private

        def convert_path(sinatra_path)
          sinatra_path.gsub(/:(\w+)/, '{\1}')
        end

        def extract_path_params(sinatra_path)
          sinatra_path.scan(/:(\w+)/).flatten.map do |name|
            param = {
              'name' => name,
              'in' => 'path',
              'required' => true,
              'schema' => { 'type' => name.end_with?('_id') ? 'integer' : 'string' }
            }
            param
          end
        end

        def build_operation(decl, top_level_scheme_names)
          operation = {}
          operation['summary'] = decl.summary if decl.summary

          parameters = extract_path_params(decl.path)
          parameters += build_query_params(decl.query_schema) if decl.query_schema

          operation['parameters'] = parameters unless parameters.empty?

          if decl.body_schema
            operation['requestBody'] = {
              'content' => {
                'application/json' => { 'schema' => decl.body_schema }
              }
            }
          end

          operation['responses'] = build_responses(decl.response_schemas)

          # Emit per-operation security only when it differs from top-level default
          if decl.security && decl.security.flat_map(&:keys).to_set != top_level_scheme_names.to_set
            operation['security'] = decl.security
          end

          operation
        end

        def build_query_params(query_schema)
          properties = query_schema['properties'] || {}
          required_fields = query_schema['required'] || []

          properties.map do |name, prop_schema|
            param = {
              'name' => name,
              'in' => 'query',
              'schema' => prop_schema
            }
            param['required'] = true if required_fields.include?(name)
            param
          end
        end

        def build_responses(response_schemas)
          return { '200' => { 'description' => 'OK' } } if response_schemas.empty?

          response_schemas.each_with_object({}) do |(status_code, schema), responses|
            key = status_code.to_s
            description = Rack::Utils::HTTP_STATUS_CODES[status_code] || 'Response'
            entry = { 'description' => description }
            entry['content'] = {
              'application/json' => { 'schema' => schema }
            }
            responses[key] = entry
          end
        end
      end
    end
  end
end
