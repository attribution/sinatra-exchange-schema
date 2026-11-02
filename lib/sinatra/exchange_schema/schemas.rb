# The named schemas an app shares across its endpoints: each declared once with the Builder DSL
# and referenced by name from a body, a response or a nested field. The generated document
# carries them under components/schemas, and a compiled schema carries the ones it references
# under the same path, so a reference resolves the same way in both.
module Sinatra
  module ExchangeSchema
    module Schemas
      PATH = '#/components/schemas/'.freeze

      class << self
        def registry
          @registry ||= {}
        end

        def define(name, &block)
          builder = Builder.new
          builder.instance_eval(&block)
          registry[name.to_s] = builder.to_json_schema
        end

        def fetch(name)
          registry.fetch(name.to_s) { raise ArgumentError, "Unknown schema: #{name.inspect}" }
        end

        # A reference to a named schema, which must already be defined.
        def ref(name)
          fetch(name)
          { '$ref' => PATH + name.to_s }
        end

        # The schema with the named schemas it references attached under the document's path, so
        # a validator resolves them; the schema as it is when it references none.
        def resolve(schema)
          names = referenced(schema)
          return schema if names.empty?

          schema.merge('components' => { 'schemas' => registry.slice(*names) })
        end

        # The names one or more schemas reference, transitively, in first-seen order.
        def referenced(*schemas, found: [])
          schemas.each do |schema|
            walk(schema) do |name|
              next if found.include?(name)

              found << name
              referenced(fetch(name), found: found)
            end
          end
          found
        end

        def clear
          registry.clear
        end

        private

        def walk(node, &block)
          case node
          when Hash
            yield node['$ref'].delete_prefix(PATH) if node['$ref'].is_a?(String) && node['$ref'].start_with?(PATH)
            node.each_value { |value| walk(value, &block) }
          when Array
            node.each { |value| walk(value, &block) }
          end
        end
      end
    end
  end
end
