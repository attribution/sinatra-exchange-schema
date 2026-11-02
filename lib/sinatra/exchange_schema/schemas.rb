# The named schemas an app shares across its endpoints: each declared once with the Builder DSL
# and referenced by name from a body, a response or a nested field. The generated document
# carries them under components/schemas, and a compiled schema carries the ones it references
# under the same path, so a reference resolves the same way in both.
module Sinatra
  module ExchangeSchema
    module Schemas
      PATH = '#/components/schemas/'.freeze
      # An OpenAPI component key: https://spec.openapis.org/oas/v3.1.0#components-object
      NAME = /\A[A-Za-z0-9._-]+\z/
      # The keywords whose values are data, not schemas, so a hash under them is never a reference;
      # so is everything under a specification extension, an x- key.
      DATA_KEYWORDS = %w[enum const default example examples].freeze
      # The keywords whose values are schemas keyed by name: a key there is a name, not a keyword.
      NAMED_SCHEMAS = %w[properties patternProperties dependentSchemas $defs definitions].freeze

      class << self
        def registry
          @registry ||= {}
        end

        # Defines a schema once: the same name again takes the same shape or raises, so one app's
        # definition never silently replaces another's.
        def define(name, &block)
          name = name.to_s
          raise ArgumentError, "Schema name #{name.inspect} must be letters, digits, dots, dashes or underscores" unless name.match?(NAME)

          builder = Builder.new
          builder.instance_eval(&block)
          schema = builder.to_json_schema
          if registry.key?(name) && registry[name] != schema
            raise ArgumentError, "Schema #{name.inspect} is already defined with another shape"
          end

          registry[name] = schema
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

        # A named schema extended by an inline one: both in an allOf, and what the extension said
        # its other keys take lifted to the wrapper as unevaluatedProperties, which sees the keys
        # the reference declares where the member's own additionalProperties would not.
        def compose(reference, extension)
          composed = { 'allOf' => [reference, extension.except('additionalProperties')] }
          composed['unevaluatedProperties'] = extension['additionalProperties'] if extension.key?('additionalProperties')
          composed
        end

        # The schema with its references followed and its allOf members merged into one, the way
        # a reader of its properties sees it. For review output, not for validation.
        def flatten(schema)
          return schema unless schema.is_a?(Hash)

          # a whole-schema reference is one more member beside the allOf's, all merged onto the
          # schema's own keywords; a deeper or foreign pointer stays where it is
          ref = ref_of(schema)
          followed = named?(ref) && ref == PATH + name_of(ref)
          members = Array(schema['allOf'])
          members = [fetch(name_of(ref)), *members] if followed
          return schema if members.empty?

          own = schema.except('allOf')
          own = own.except('$ref', :'$ref') if followed
          members.map { |member| flatten(member) }.select { |member| member.is_a?(Hash) }.reduce(own) do |merged, member|
            merged.merge(member) do |key, mine, theirs|
              case key
              when 'properties' then mine.merge(theirs)
              when 'required' then (mine + theirs).uniq
              else theirs
              end
            end
          end
        end

        def clear
          registry.clear
        end

        private

        # The reference a schema carries, under a string or a symbol key, as json_schemer reads both.
        def ref_of(node)
          node['$ref'] || node[:'$ref']
        end

        # A reference into the named schemas; any other pointer is left to its own document.
        def named?(ref)
          ref.is_a?(String) && ref.start_with?(PATH)
        end

        # The schema a reference points into: the first segment past the path, a pointer deeper
        # into it resolving within that schema once it is attached.
        def name_of(ref)
          ref.delete_prefix(PATH).split('/').first
        end

        def walk(node, &block)
          case node
          when Hash
            yield name_of(ref_of(node)) if named?(ref_of(node))
            node.each do |key, value|
              key = key.to_s
              next if DATA_KEYWORDS.include?(key) || key.start_with?('x-')

              if NAMED_SCHEMAS.include?(key) && value.is_a?(Hash)
                value.each_value { |child| walk(child, &block) }
              else
                walk(value, &block)
              end
            end
          when Array
            node.each { |value| walk(value, &block) }
          end
        end
      end
    end
  end
end
