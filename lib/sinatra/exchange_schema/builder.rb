# Compiles a Ruby DSL into a JSON Schema hash.
# Used by EndpointDeclaration to define request body and query schemas inline.
#
# Scalar types: string, integer, number, boolean
# Compound types: array (with +items+ block or hash), object (with nested block)
#
# == Usage
#
#   builder = Builder.new
#   builder.instance_eval do
#     string  :name, required: true
#     string  :status, enum: %w[active archived]
#     integer :page
#     object  :metadata do
#       string :source
#     end
#     array :tags do
#       string :value
#     end
#   end
#   builder.to_json_schema
#   # => { "type" => "object",
#   #      "properties" => { "name" => { "type" => "string" }, ... },
#   #      "required" => ["name"] }
#
module Sinatra
  module ExchangeSchema
    class Builder
      TYPES = %w[string integer number boolean].freeze

      attr_reader :properties, :required_fields

      def initialize
        @properties = {}
        @required_fields = []
      end

      TYPES.each do |type|
        define_method(type) do |name, **opts|
          name = name.to_s
          prop = { 'type' => opts[:nullable] ? [type, 'null'] : type }
          prop['enum'] = opts[:enum] if opts[:enum]
          @properties[name] = prop
          @required_fields << name if opts[:required]
        end
      end

      def array(name, items: nil, required: false, nullable: false, &block)
        name = name.to_s
        prop = { 'type' => nullable ? %w[array null] : 'array' }
        if block
          nested = self.class.new
          nested.instance_eval(&block)
          prop['items'] = nested.to_json_schema
        elsif items
          prop['items'] = items
        end
        @properties[name] = prop
        @required_fields << name if required
      end

      def object(name, required: false, &block)
        name = name.to_s
        nested = self.class.new
        nested.instance_eval(&block)
        @properties[name] = nested.to_json_schema
        @required_fields << name if required
      end

      def to_json_schema
        schema = {
          'type' => 'object',
          'properties' => @properties
        }
        schema['required'] = @required_fields unless @required_fields.empty?
        schema
      end
    end
  end
end
