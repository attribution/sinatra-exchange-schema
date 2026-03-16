# Sinatra extension that provides an +endpoint+ DSL for declaring
# request and response schemas on routes. Validates incoming requests
# and outgoing responses using a three-level mode system:
# app-wide, per-controller, and per-endpoint.
#
# Each validation concern (+request_validation+, +response_validation+,
# +missing_schema+) can be set to +:off+, +:warn+, or +:strict+.
#
# == Usage
#
#   set :endpoint_security, :bearer
#
#   endpoint :post, '/v2/widgets' do
#     summary 'Create widget'
#     request_validation :strict
#     body do
#       string :name, required: true
#     end
#   end
#
#   # For endpoints returning arrays of primitives, use items: instead of a block.
#   # The type describes each array item; the after-filter unwraps and validates.
#   endpoint :get, '/v2/properties' do
#     summary 'List property keys'
#     response 200, items: :string
#   end
#
require 'json'
require 'sinatra/base'
require_relative 'exchange_schema/version'
require_relative 'exchange_schema/builder'
require_relative 'exchange_schema/endpoint_declaration'
require_relative 'exchange_schema/request_validator'
require_relative 'exchange_schema/response_validator'
require_relative 'exchange_schema/openapi_generator'

module Sinatra
  module ExchangeSchema
    class MissingEndpointSchemaError < StandardError; end

    VALID_MODES = %i[off warn strict].freeze

    class << self
      attr_reader :request_validation, :response_validation, :missing_schema

      def request_validation=(mode)
        validate_mode!(mode)
        @request_validation = mode
      end

      def response_validation=(mode)
        validate_mode!(mode)
        @response_validation = mode
      end

      def missing_schema=(mode)
        validate_mode!(mode)
        @missing_schema = mode
      end

      private

      def validate_mode!(mode)
        return if VALID_MODES.include?(mode)

        raise ArgumentError, "Invalid mode #{mode.inspect}, must be one of #{VALID_MODES.inspect}"
      end
    end

    # App-wide defaults
    self.request_validation = :warn
    self.response_validation = :warn
    self.missing_schema = :warn

    # Called when a Sinatra app registers this extension.
    def self.registered(app)
      app.set :endpoint_declarations, [] unless app.respond_to?(:endpoint_declarations)
      app.set :endpoint_security, nil
      app.set :request_validation, nil
      app.set :response_validation, nil
      app.set :missing_schema, nil
      app.set :openapi_file, nil

      app.before do
        declaration = self.class.endpoint_declarations.find do |decl|
          decl.matches?(request.request_method, request.path_info)
        end
        next unless declaration

        env['endpoint_schema.declaration'] = declaration

        if declaration.body_schema && request.request_method != 'GET'
          begin
            request.body.rewind unless request.body.pos.zero?
            body_str = request.body.read
            request.body.rewind
            unless body_str.empty?
              payload = ::JSON.parse(body_str)
              payloads = payload.is_a?(Array) ? payload : [payload]
              payloads.each do |item|
                errors = ::Sinatra::ExchangeSchema::RequestValidator.call(item, declaration.body_schema)
                next unless errors

                context = { method: request.request_method, path: request.path_info, errors: errors }
                message = "Endpoint schema validation failed: #{context[:method]} #{context[:path]}"
                mode = ExchangeSchema.effective_mode(declaration, :request_validation, settings)
                ExchangeSchema.dispatch(mode, :request_validation, message, context, self)
              end
            end
          rescue ::JSON::ParserError
            # Body parsing is handled elsewhere; skip validation
          end
        end

        if declaration.query_schema
          query_hash = params.reject { |k, _| k.start_with?('splat', 'captures') }
          declaration.path.scan(/:(\w+)/).flatten.each { |p| query_hash.delete(p) }
          errors = ::Sinatra::ExchangeSchema::RequestValidator.call(query_hash, declaration.query_schema)
          if errors
            context = { method: request.request_method, path: request.path_info, errors: errors }
            message = "Endpoint schema validation failed: #{context[:method]} #{context[:path]}"
            mode = ExchangeSchema.effective_mode(declaration, :request_validation, settings)
            ExchangeSchema.dispatch(mode, :request_validation, message, context, self)
          end
        end
      end

      app.after do
        declaration = env['endpoint_schema.declaration']
        next unless declaration
        next if declaration.response_schemas.empty?

        schema = declaration.response_schemas[response.status]
        next unless schema

        begin
          body_str = response.body.is_a?(Array) ? response.body.join : response.body.to_s
          next if body_str.empty?

          payload = ::JSON.parse(body_str)
          payloads = payload.is_a?(Array) ? payload : [payload]
          payloads.each do |item|
            errors = ::Sinatra::ExchangeSchema::ResponseValidator.call(item, schema)
            next unless errors

            context = { method: request.request_method, path: request.path_info,
                        status: response.status, errors: errors }
            message = "Response schema validation failed: #{context[:method]} #{context[:path]} #{context[:status]}"
            mode = ExchangeSchema.effective_mode(declaration, :response_validation, settings)
            ExchangeSchema.dispatch(mode, :response_validation, message, context, self)
          end
        rescue ::JSON::ParserError
          # Non-JSON responses (streaming, plain text) — skip validation
        end
      end

      # Warn about routes that have no endpoint schema declared
      app.after do
        next unless env['sinatra.route']
        next if env['endpoint_schema.declaration']
        next if %w[OPTIONS HEAD].include?(request.request_method)

        mode = ExchangeSchema.effective_mode(nil, :missing_schema, settings)
        next if mode == :off

        context = { method: request.request_method, path: request.path_info, errors: [] }
        message = "No endpoint schema declared for #{context[:method]} #{context[:path]}"
        ExchangeSchema.dispatch(mode, :missing_schema, message, context, self)
      end
    end

    # Resolve the effective mode for a concern, checking endpoint > controller > app-wide.
    def self.effective_mode(declaration, concern, controller_settings)
      if %i[request_validation response_validation].include?(concern)
        endpoint_val = declaration&.send(concern)
        return endpoint_val if endpoint_val
      end

      controller_val = controller_settings.respond_to?(concern) ? controller_settings.send(concern) : nil
      return controller_val if controller_val

      send(concern)
    end

    # Dispatch a warning/error based on the effective mode.
    def self.dispatch(mode, type, message, context, controller_instance)
      return if mode == :off

      if controller_instance.respond_to?(:on_exchange_schema_warning)
        controller_instance.on_exchange_schema_warning(type, message, context)
      else
        controller_instance.logger.warn(message)
      end

      return unless mode == :strict

      case type
      when :request_validation
        raise RequestValidator::SchemaValidationError, "#{message} — #{context[:errors]}"
      when :response_validation
        raise ResponseValidator::ResponseSchemaValidationError, "#{message} — #{context[:errors]}"
      when :missing_schema
        raise MissingEndpointSchemaError, message
      end
    end

    # Declare an endpoint schema. Place directly above the corresponding
    # route handler. Accepts an optional block with +body+, +query+,
    # and/or +response+ sub-blocks that use the Builder DSL.
    def endpoint(http_method, path, &block)
      decl = ::Sinatra::ExchangeSchema::EndpointDeclaration.new(http_method, path)
      decl.instance_eval(&block) if block
      if !decl.security && settings.respond_to?(:endpoint_security) && settings.endpoint_security
        decl.security(settings.endpoint_security)
      end
      if !decl.openapi_file && settings.respond_to?(:openapi_file) && settings.openapi_file
        decl.openapi_file(settings.openapi_file)
      end
      endpoint_declarations << decl
    end
  end

  register ExchangeSchema
end
