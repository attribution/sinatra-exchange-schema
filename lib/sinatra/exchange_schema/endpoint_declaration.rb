# Holds metadata for a single endpoint: HTTP method, path, summary,
# and optional body/query/response JSON Schemas built via ExchangeSchema::Builder.
#
# Instances are created by the +endpoint+ DSL in Sinatra::ExchangeSchema
# and stored on the controller class. The before-filter validates requests
# and the after-filter validates responses.
require_relative 'builder'

module Sinatra
  module ExchangeSchema
    class EndpointDeclaration
      AUTH_SCHEMES = {
        'bearer' => { 'type' => 'http', 'scheme' => 'bearer' },
        'basic'  => { 'type' => 'http', 'scheme' => 'basic' }
      }.freeze

      attr_reader :http_method, :path,
                  :body_schema, :query_schema, :response_schemas

      def initialize(http_method, path)
        @http_method = http_method.to_s.upcase
        @path = path
        @response_schemas = {}
      end

      def summary(value = :_unset)
        return @summary if value == :_unset

        @summary = value
      end

      def request_validation(value = :_unset)
        return @request_validation if value == :_unset

        @request_validation = value
      end

      def response_validation(value = :_unset)
        return @response_validation if value == :_unset

        @response_validation = value
      end

      def openapi_file(value = :_unset)
        return @openapi_file if value == :_unset

        @openapi_file = value
      end

      def security(value = :_unset)
        return @security if value == :_unset

        @security = case value
                    when :none then []
                    when Symbol
                      name = value.to_s
                      AUTH_SCHEMES.fetch(name) { raise ArgumentError, "Unknown auth: #{value}" }
                      [{ name => [] }]
                    else value
                    end
      end

      # Define a JSON Schema for the request body.
      # The block is evaluated in the context of a ExchangeSchema::Builder.
      def body(&block)
        builder = Builder.new
        builder.instance_eval(&block)
        @body_schema = builder.to_json_schema
      end

      # Define a JSON Schema for query-string parameters.
      # The block is evaluated in the context of a ExchangeSchema::Builder.
      def query(&block)
        builder = Builder.new
        builder.instance_eval(&block)
        @query_schema = builder.to_json_schema
      end

      # Define a JSON Schema for a response status code.
      # When +items:+ is given, produces a simple type schema (e.g. { "type" => "string" }).
      # Otherwise the block is evaluated in the context of a ExchangeSchema::Builder.
      def response(status_code, items: nil, &block)
        schema = if items
          { 'type' => items.to_s }
        else
          builder = Builder.new
          builder.instance_eval(&block) if block
          builder.to_json_schema
        end
        @response_schemas[status_code.to_i] = schema
      end

      # Convert Sinatra-style path to a regex for matching requests.
      # Path params like +:filter_id+ become named capture groups.
      def path_regex
        @path_regex ||= begin
          # Escape dots in static segments:
          # "/v2/data.json/:id" => \A/v2/data\.json/(?<id>[^/]+)\z
          parts = path.split(/:(\w+)/)
          pattern = parts.each_slice(2).map do |static, param|
            escaped = Regexp.escape(static)
            param ? "#{escaped}(?<#{param}>[^/]+)" : escaped
          end.join
          Regexp.new("\\A#{pattern}\\z")
        end
      end

      # Returns true when the given HTTP method and path match this declaration.
      def matches?(request_method, request_path)
        request_method.upcase == http_method && path_regex.match?(request_path)
      end
    end
  end
end
