# Compiles a Ruby DSL into a JSON Schema hash.
# Used by EndpointDeclaration to define request body and query schemas inline.
#
# Scalar types: string, integer, number, boolean
# Compound types: array (with +items+ block, symbol, or hash), object (with nested block),
# map (an object keyed by data, with +values+ symbol or hash, or a nested block)
#
# == Usage
#
#   builder = Builder.new
#   builder.instance_eval do
#     string  :name, required: true
#     string  :status, enum: %w[active archived]
#     string  :since, format: :date
#     integer :page
#     object  :metadata do
#       string :source
#     end
#     array :tags do
#       string :value
#     end
#     map :totals, values: :integer
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
          existing_types = Array(@properties.dig(name, 'type'))
          types = (existing_types.reject { |t| t == 'null' } + [type]).uniq
          types += ['null'] if opts[:nullable] || existing_types.include?('null')
          prop = (@properties[name] || {}).merge('type' => types.one? ? types.first : types)
          prop['enum'] = opts[:enum] if opts[:enum]
          prop['format'] = opts[:format].to_s if opts[:format]
          prop['description'] = opts[:description] if opts[:description]
          @properties[name] = prop
          @required_fields << name if opts[:required] && !@required_fields.include?(name)
        end
      end

      def array(name, items: nil, required: false, nullable: false, description: nil, &block)
        name = name.to_s
        prop = { 'type' => nullable ? %w[array null] : 'array' }
        if block
          nested = self.class.new
          nested.instance_eval(&block)
          prop['items'] = nested.to_json_schema
        elsif items
          prop['items'] = items.is_a?(Symbol) ? { 'type' => items.to_s } : items
        end
        prop['description'] = description if description
        @properties[name] = prop
        @required_fields << name if required
      end

      def object(name, required: false, nullable: false, description: nil, &block)
        name = name.to_s
        if block
          nested = self.class.new
          nested.instance_eval(&block)
          schema = nested.to_json_schema
          schema['description'] = description if description
          @properties[name] = schema
        else
          prop = { 'type' => nullable ? %w[object null] : 'object' }
          prop['description'] = description if description
          @properties[name] = prop
        end
        @required_fields << name if required
      end

      # An object whose keys are data (ids, dates, names) and whose values share one schema: a
      # +values+ symbol names a scalar type, a +values+ hash is used as the schema, a block builds
      # the value object. Emitted as +additionalProperties+, so the validator checks every value.
      def map(name, values: nil, required: false, nullable: false, description: nil, &block)
        name = name.to_s
        prop = { 'type' => nullable ? %w[object null] : 'object' }
        prop['additionalProperties'] = if block
          nested = self.class.new
          nested.instance_eval(&block)
          nested.to_json_schema
        elsif values
          values.is_a?(Symbol) ? { 'type' => values.to_s } : values
        else
          raise ArgumentError, "map #{name.inspect} needs values: or a block"
        end
        prop['description'] = description if description
        @properties[name] = prop
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
