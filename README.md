# sinatra-exchange-schema

Sinatra extension that adds an `endpoint` DSL for declaring request/response JSON schemas on routes. Validates payloads at runtime and generates an OpenAPI 3.1 spec from the declarations.

## Installation

Add to your Gemfile:

```ruby
gem 'sinatra-exchange-schema', github: 'attribution/sinatra-exchange-schema'
```

Requires Ruby 3.0 or newer. Validation runs on [json_schemer](https://github.com/davishmcclurg/json_schemer) 2.x with
its default options, so `format` keywords are checked, not just documented.

## Quick Start

Register the extension, declare an endpoint above its route, and the declaration does two jobs at once: it validates
traffic as it flows through, and it is the source the OpenAPI document is generated from.

```ruby
require 'sinatra/exchange_schema'

class App < Sinatra::Base
  register Sinatra::ExchangeSchema

  endpoint :post, '/articles' do
    summary 'Create an article'
    body do
      string :name, required: true
    end
    response 201 do
      integer :id, required: true
      string  :name, required: true
    end
  end

  post '/articles' do
    status 201
    { id: 1, name: params['name'] }.to_json
  end
end
```

A request with a misspelled key, `{"nmae": "First"}`, logs

```
Endpoint schema validation failed: POST /articles
```

and goes on to the route, because the default mode is `:warn`. Switch to `:strict` to reject it — see
[Runtime Validation](#runtime-validation). To write the spec, install the rake task and run it — see
[OpenAPI Generation](#openapi-generation).

## Declaring Endpoints

Place `endpoint` blocks above your route handlers. A declaration is matched to a request by method and path, so the
position is a convention for readers, not a requirement. The block accepts `summary`, `body`, `query`, `path`,
`response`, `security`, `data_types` and the per-endpoint settings described further down.

Declarations made in a subclass are stored on the base class as well, so one base controller holds every endpoint of
the app; the rake task and the programmatic generator read them from there.

### Request Body

```ruby
endpoint :post, '/articles' do
  summary 'Create an article'

  body do
    string  :name, required: true, description: 'Title of the article'
    string  :status, enum: %w[active archived]
    integer :priority
    boolean :published, nullable: true
    object  :metadata do
      string :source
    end
    object  :extra_options
    array :tags do
      string :value
    end
  end
end
```

The body is validated for every method but `GET`. A body that is not valid JSON is skipped, since parsing it is the
route's job; a body that cannot be rewound is skipped with a warning. Keys the body does not declare are violations by
default — see [Undeclared Body Keys](#undeclared-body-keys).

### Query Parameters

```ruby
endpoint :get, '/articles' do
  summary 'List articles'

  query do
    string :status, required: true, enum: %w[active archived], description: 'Filter by status'
    string :page, nullable: true
    string :per_page
  end
end
```

Query values reach the validator as the strings Sinatra parsed them into, with no coercion, so a parameter declared
`integer` fails for `?page=2` ([#15](https://github.com/attribution/sinatra-exchange-schema/issues/15)). Declare
query parameters as strings until that lands. Path parameters are removed from the hash before it is validated, and
keys the block does not declare are always allowed — proxies, analytics and cache-busting add their own.

### Path Parameters

A path parameter gets its OpenAPI type from its name: one ending in `_id` is documented as an
`integer`, any other as a `string`. When the name misleads — a UUID, a slug or another service's
id behind an `_id` placeholder — a `path` block declares the type:

```ruby
endpoint :get, '/articles/:article_id/uploads/:upload_id' do
  summary 'Get an upload'

  path do
    string :upload_id, description: 'UUID of the upload'
  end
end
```

A parameter the block leaves out keeps the name-based type, so `article_id` above stays an
`integer`. Every path parameter is `required: true` whatever the block says, because OpenAPI
requires it. Naming a parameter the route does not have raises when the endpoint is declared.

The block shapes the generated contract only: Sinatra hands path parameters over as strings, and
runtime validation covers the body and the query.

### Responses

`response` takes a status code and declares the body sent with it. Declare every status the route answers with,
including its failures: only declared statuses are validated, and only declared statuses appear in the spec.

```ruby
endpoint :post, '/articles' do
  summary 'Create an article'

  body do
    string :name, required: true
  end

  response 201 do
    integer :id, required: true
    string  :name, required: true
  end

  response 422 do
    string :error, required: true
  end
end
```

Two shorthands cover the edges. `response 200` with no block declares an object of any shape: the status is documented
and the body is checked to be an object, nothing more. An endpoint with no `response` at all is documented as a
bare `200 OK` with no content, and its body is never validated.

A status holds one form per media type, so declaring the same JSON status twice keeps the last declaration.
A second form under another media type is added beside it — see [Non-JSON Responses](#non-json-responses).

#### Array Responses

When an endpoint returns a top-level array, use `response` with the `items:` keyword argument. The generated schema is `{ type: 'array', items: <element schema> }` — OpenAPI and validation both see an array, not a bare element.

```ruby
# Array of strings — e.g. ["key1", "key2", "key3"]
endpoint :get, '/tags' do
  summary 'List tags'
  response 200, items: :string
end

# Array of arrays (tuples) — e.g. [["value", 1], ["other", 2]]
endpoint :get, '/tags/filtered/:key' do
  summary 'Tag values with counts'
  response 200, items: :array
end

# Array of objects — e.g. [{"id": 1, "name": "First"}, ...]
endpoint :get, '/articles' do
  summary 'List articles'
  response 200, items: :object do
    integer :id, required: true
    string  :name, required: true
  end
end
```

Supported element types: `:string`, `:integer`, `:number`, `:boolean`, `:array`, `:object` (with a block), or a schema hash.

The same symbol syntax works in the `array` field DSL inside `body`/`query`/`response` blocks — e.g. `array :tags, items: :string`.

#### Map Responses

When the top-level body is an object keyed by data — ids, names — use `response` with `values:`, the way `items:` declares
an array. The generated schema is `{ type: 'object', additionalProperties: <value schema> }`, so the validator checks
every value whatever its key.

```ruby
# Keyed by id, a result per key — e.g. {"17": true, "42": "not found"}
endpoint :delete, '/articles' do
  summary 'Delete articles'
  response 200, values: { 'type' => %w[boolean string] }
end

# Keyed by name, an object per key — e.g. {"draft": {"count": 3}, "published": {"count": 9}}
endpoint :get, '/articles/by_status' do
  summary 'Articles per status'
  response 200, values: :object do
    integer :count, required: true
  end
end
```

Inside a block, `map` declares the same shape as a property — see [Schema Builder DSL](#schema-builder-dsl).

#### Non-JSON Responses

A body that is not JSON — a CSV file, plain text — is declared by its media type alone. The generated spec publishes the
success under that media type with a string schema, and the response filter leaves the body alone, even when it happens to
parse as JSON. A schema block or `items:` with such a content type raises, since there is nothing to build.

```ruby
endpoint :get, '/articles.csv' do
  summary 'Articles as CSV'
  response 200, content: 'text/csv'
end
```

A status may take several forms, one per media type — a CSV file, or a JSON body when no file could be made. Each
`response` adds or replaces the form of its media type; the spec lists them all under the status, and the filter
validates a JSON body against the JSON form and leaves the others alone, going by the `Content-Type` the route sends.

```ruby
endpoint :get, '/articles.csv' do
  summary 'Articles as CSV, or why there is no file'
  response 200, content: 'text/csv'
  response 200 do
    string :error, required: true, description: 'Why no file came back'
  end
end
```

### Security

A default security scheme is set at the app level, above the `endpoint` blocks it should apply to:

```ruby
class App < Sinatra::Base
  register Sinatra::ExchangeSchema
  set :endpoint_security, :bearer
end
```

Supported schemes: `:bearer` (HTTP Bearer token) and `:basic` (HTTP Basic). Individual endpoints override the default,
and `:none` marks an endpoint as public:

```ruby
endpoint :get, '/health' do
  security :none
end
```

`scopes:` records the OAuth scopes a scheme needs for the endpoint. They go into the spec's security requirement and
are readable at request time through the `current_endpoint_declaration` helper, so an authorization check can be
driven by the declaration instead of a second list:

```ruby
endpoint :get, '/articles/:id' do
  security :bearer, scopes: ['articles:read']
end

before do
  required = current_endpoint_declaration&.scopes || []
  halt 403 unless (required - token_scopes).empty?
end
```

`security` also accepts a raw OpenAPI security requirement array, for a scheme the symbols do not cover.

### Data Types

`data_types` declares what customer data the endpoint's success payloads can expose, as free-form snake_case tokens (`/\A[a-z][a-z0-9_]*\z/`; anything else raises at declaration time). It is optional and has no runtime effect: absent means the endpoint was not assessed, `:none` means assessed and exposes nothing. Declare the union across query-param variants — if `?include=address` adds the postal address, declare it too.

```ruby
endpoint :get, '/users/:id' do
  security :bearer, scopes: ['users:read']
  data_types :email, :postal_address
end

endpoint :get, '/health' do
  security :none
  data_types :none
end
```

The OpenAPI generator emits it as the `x-data-types` extension on the operation (`[]` for `:none`, omitted when not declared). Use `rake exchange_schema:data_types` to review declarations side by side — see [Rake Task](#rake-task).

## Schema Builder DSL

The `body`, `query`, `path`, and `response` blocks use a builder DSL with these types. (For `response`, you can also pass `items:` or `values:` directly — see [Responses](#responses) above.)

| Method    | Options                                  |
|-----------|------------------------------------------|
| `string`  | `required:`, `enum:`, `format:`, `nullable:`, `description:` |
| `integer` | `required:`, `enum:`, `format:`, `nullable:`, `description:` |
| `number`  | `required:`, `enum:`, `format:`, `nullable:`, `description:` |
| `boolean` | `required:`, `nullable:`, `description:`           |
| `array`   | `required:`, `nullable:`, `items:`, `description:`, block |
| `object`  | `required:`, `nullable:`, `description:`, block (optional) |
| `map`     | `required:`, `nullable:`, `values:`, `description:`, block |

`format:` takes a JSON Schema format name (`date`, `date-time`, `email`, `uri`, …). json_schemer validates it under the
gem's default options, so `string :start_date, format: :date` rejects `2026-13-01` at request time, and the OpenAPI
generator emits it on the property.

`object` with a block declares its properties; without one it declares an object of any shape. `nullable:` takes
effect on the blockless form only — with a block it is dropped
([#16](https://github.com/attribution/sinatra-exchange-schema/issues/16)).

`map` declares an object whose keys are data — ids, dates, names — and whose values share one schema, emitted as
`additionalProperties` so the validator checks every value and the spec documents the map. `values:` takes a scalar
type symbol or any schema hash (an array, another map); a block builds the value object.

```ruby
response 200 do
  map :totals, values: :integer, description: 'Count per status'
  map :articles, description: 'Keyed by article id' do
    string  :name, required: true
    integer :views
  end
end
```

A property that takes more than one scalar type is declared once per type under the same name; the types merge into a
union:

```ruby
body do
  string  :id
  integer :id    # => { "type": ["string", "integer"] }
end
```

## Runtime Validation

Once registered, the extension installs before/after filters that automatically validate requests and responses against declared schemas. Three independent concerns control behavior:

| Concern               | What it checks                                      |
|-----------------------|-----------------------------------------------------|
| `request_validation`  | JSON body and query params vs declared schemas      |
| `response_validation` | JSON response body vs `response` schemas            |
| `missing_schema`      | Routes that have no `endpoint` declaration at all   |

Each concern accepts one of three modes:

| Mode      | Behavior                       |
|-----------|--------------------------------|
| `:off`    | Skip validation entirely       |
| `:warn`   | Log a warning **(default)**    |
| `:strict` | Log a warning **and** raise    |

A fourth setting, `additional_properties`, is a boolean rather than a mode — see below.

### What Gets Validated

- **Request body** — every method but `GET`, against the `body` schema. A body that is not valid JSON is skipped;
  a body that cannot be rewound is skipped with a warning.
- **Query** — against the `query` schema, as strings, with path parameters removed and undeclared keys allowed.
- **Response body** — only a status the endpoint declared, against its JSON form; a `500`, or a `422` the endpoint
  never declared, passes unchecked. A status with no JSON form is never validated; one with several forms is
  validated only when the `Content-Type` sent is `application/json`. An empty body passes.
- **Missing schema** — a routed request with no matching declaration. `OPTIONS` and `HEAD` are exempt.

An array payload against an object-typed schema — a request body that is a JSON array, or a response that returns an
array where an object was declared — is validated element by element instead of failing. This unwrap is scheduled
for removal ([#17](https://github.com/attribution/sinatra-exchange-schema/issues/17)); declare a top-level array
with `items:`.

### Undeclared Body Keys

JSON Schema allows any key a `body` did not declare, so without this an endpoint answers 200 to
`descripton` and does nothing with it — the client is never told it misspelled anything.

`additional_properties` is the JSON Schema keyword of the same name, lifted to a setting. It
defaults to `false`, so an undeclared key is a violation; an app that is not ready for that turns
it back on:

```ruby
Sinatra::ExchangeSchema.additional_properties = true   # default: false
```

This is orthogonal to the modes above: `additional_properties` decides what counts as a
violation, `request_validation` decides what happens to one. Leaving it closed while
`request_validation` is `:warn` reports undeclared keys without rejecting them — the way to find
out what real clients send before turning the screw.

It also keeps the generated OpenAPI honest: an endpoint that reads a key has to declare it.

Two deliberate exceptions:

- **Nested objects stay open.** `object :settings` with no block declares no properties, so
  closing it would reject every key inside.
- **Query parameters stay open.** Proxies, analytics and cache-busting add their own.

An endpoint that genuinely accepts arbitrary keys — a third-party webhook whose payload you
do not control — opts out for itself:

```ruby
endpoint :post, '/webhook' do
  additional_properties true
  body do
    string :event
  end
end
```

### Configuration Levels

Settings are resolved with **endpoint > controller > app-wide** precedence.

**App-wide** — sets the global default for all controllers:

```ruby
Sinatra::ExchangeSchema.request_validation    = :strict
Sinatra::ExchangeSchema.response_validation   = :off
Sinatra::ExchangeSchema.missing_schema        = :warn
Sinatra::ExchangeSchema.additional_properties = true
```

**Per-controller** — overrides the app-wide default for a single Sinatra class:

```ruby
class Api < Sinatra::Base
  register Sinatra::ExchangeSchema
  set :request_validation, :strict
  set :additional_properties, true
end
```

**Per-endpoint** — overrides both app-wide and controller settings for one route:

```ruby
endpoint :post, '/articles' do
  request_validation :strict
  response_validation :off
  additional_properties true
  body do
    string :name, required: true
  end
end
```

Leaving a level unset means "inherit"; an explicit value at a lower level wins over the one
above it, including `additional_properties true` under an app-wide `false`. `missing_schema` has no per-endpoint level — it fires precisely when no
declaration matched.

`additional_properties`, `endpoint_security` and `openapi_file` are read once, when the endpoint is declared, so
their `set` must appear above the `endpoint` blocks it should affect. The validation modes are read per request and
can be set anywhere.

### Strict Mode and Clients

In `:strict` mode a violation raises after the warning is reported:

| Concern               | Raises                                                              |
|-----------------------|---------------------------------------------------------------------|
| `request_validation`  | `Sinatra::ExchangeSchema::RequestValidator::SchemaValidationError`    |
| `response_validation` | `Sinatra::ExchangeSchema::ResponseValidator::ResponseSchemaValidationError` |
| `missing_schema`      | `Sinatra::ExchangeSchema::MissingEndpointSchemaError`                 |

Left alone, a request error surfaces as Sinatra's 500. To answer the client with the violation instead, keep the
errors from the warning callback and render them from an `error` handler:

```ruby
def on_exchange_schema_warning(type, message, context)
  logger.warn(message)
  env['exchange_schema.errors'] = context[:errors] if type == :request_validation
end

error Sinatra::ExchangeSchema::RequestValidator::SchemaValidationError do
  status 422
  { errors: env['exchange_schema.errors'] }.to_json
end
```

Each error is a hash with `field` (a JSON pointer), `error`, `type` and `actual_value`. The response error is raised
in an after filter, once the route has run; it is a signal for tests and staging, not something a client should see.

### Strict in Tests

A common pattern is to make all validation strict in the test environment:

```ruby
# spec/spec_helper.rb
Sinatra::ExchangeSchema.request_validation  = :strict
Sinatra::ExchangeSchema.response_validation = :strict
Sinatra::ExchangeSchema.missing_schema      = :strict
```

### Warning Handler

By default, validation warnings are sent to `logger.warn`. To route them to a
custom reporter (e.g. Rollbar, Sentry), define an `on_exchange_schema_warning`
instance method on your controller:

```ruby
def on_exchange_schema_warning(type, message, context)
  # type    — :request_validation, :response_validation, or :missing_schema
  # message — human-readable description
  # context — { method:, path:, errors: [, status:] }
  #           :status is present only for response validation
  Rollbar.warning(message, type: type, **context)
end
```

In `:strict` mode the callback fires *before* the error is raised, so warnings
are still reported even when the request is halted.

## OpenAPI Generation

The gem can generate an OpenAPI 3.1 YAML spec from your endpoint declarations.

### Rake Task

Require the rake task explicitly (it is **not** auto-required):

```ruby
# tasks/exchange_schema.rake
require 'sinatra/exchange_schema/rake_task'

Sinatra::ExchangeSchema::RakeTask.install(
  app: -> { MyApp::Controllers::Base },
  info: { title: 'My API', version: 'v1' }
)
```

`app:` names the base controller: declarations from every controller that inherits from it accumulate there, so one
class covers the whole app.

Then run:

```bash
bundle exec rake exchange_schema:openapi
```

Options:

| Parameter     | Default          | Description                        |
|---------------|------------------|------------------------------------|
| `app:`        | *(required)*     | App class or lambda returning one  |
| `info:`       | `{}`             | OpenAPI info (`title`, `version`, `description`) |
| `output:`     | `./openapi.yaml` | Output file path (or `ENV['OUTPUT']`) |
| `depends_on:` | `:environment`   | Rake task prerequisites            |

`install` also defines `exchange_schema:data_types`, a review dump of every declaration: endpoint, scopes, declared data types and the top-level properties of its first 2xx response, one aligned row each (`-` = not assessed, `none` = assessed, exposes nothing). `DISTINCT=1` prints the distinct data type tokens with the number of endpoints declaring each instead.

```bash
bundle exec rake exchange_schema:data_types
DISTINCT=1 bundle exec rake exchange_schema:data_types
```

### Multi-File Output

By default every endpoint is written to the single output file (e.g. `openapi.yaml`). You can route endpoints to separate files with the `openapi_file` setting.

You can override it per-controller (`set :openapi_file, 'admin.yaml'`, above the `endpoint` blocks) or per-endpoint (`openapi_file 'articles.yaml'`). Use `openapi_file false` to exclude an endpoint from all spec files entirely.

Precedence: **endpoint > controller > default "openapi.yaml"**.

### Programmatic

```ruby
require 'sinatra/exchange_schema'

declarations = MyApp::Controllers::Base.endpoint_declarations
doc = Sinatra::ExchangeSchema::OpenapiGenerator.call(
  declarations,
  info: { title: 'My API', version: 'v1' }
)
```

## Limitations

The DSL covers the keywords above and no others. Not yet expressible:

- Shared schemas — `$ref` to `components/schemas`, and `allOf` to extend one
  ([#14](https://github.com/attribution/sinatra-exchange-schema/issues/14))
- Alternatives — `oneOf`, `anyOf` ([#2](https://github.com/attribution/sinatra-exchange-schema/issues/2))
- Value constraints — `minimum`, `maximum`, `minLength`, `maxLength`, `pattern`, `default`
- Header parameters
- Query parameter coercion ([#15](https://github.com/attribution/sinatra-exchange-schema/issues/15))

A schema hash passed as `items:` or `values:` is emitted and validated as it is, so any JSON Schema keyword works
there, without a DSL verb.

## Development

```bash
bundle install
bundle exec rspec
```
