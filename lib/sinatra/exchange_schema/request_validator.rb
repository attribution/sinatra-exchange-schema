# Validates a request payload against a JSON Schema hash.
#
# Returns an array of formatted error hashes, or nil if validation passes.
# The calling code in ExchangeSchema handles warning/raise dispatch based
# on the effective validation mode.
require 'json_schemer'

module Sinatra
  module ExchangeSchema
    class RequestValidator
      class SchemaValidationError < StandardError; end

      def self.call(payload, schema_hash)
        return if schema_hash.nil?

        schemer = JSONSchemer.schema(schema_hash)
        errors = schemer.validate(payload).to_a
        return if errors.empty?

        errors.map do |err|
          { field: err['data_pointer'], error: err['error'], type: err['type'] }
        end
      end
    end
  end
end
