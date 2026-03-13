# sinatra-exchange-schema

Sinatra extension that adds an `endpoint` DSL for declaring request/response JSON schemas on routes. Validates payloads at runtime and generates an OpenAPI 3.0 spec from the declarations.

## Installation

Add to your Gemfile:

```ruby
gem 'sinatra-exchange-schema', github: 'attribution/sinatra-exchange-schema'
```

## Setup

Register the extension on your Sinatra app:

```ruby
require 'sinatra/exchange_schema'

class App < Sinatra::Base
  register Sinatra::ExchangeSchema

  # Optional: set a default auth scheme for all endpoints
  set :endpoint_security, :bearer
end
```

## Declaring Endpoints

Place `endpoint` blocks above your route handlers. The block accepts `summary`, `body`, `query`, `response`, and `security` directives.

```ruby
endpoint :post, '/v2/widgets' do
  summary 'Create a widget'

  body do
    string  :name, required: true, description: 'Full name of the widget'
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

  response 200 do
    integer :id, required: true
    string  :name, required: true
  end
end

post '/v2/widgets' do
  # ...
end
```

### Primitive-Type Responses

When an endpoint returns an array of primitives (strings, numbers, tuples) instead of objects, use `response` with the `items:` keyword argument instead of a block. The type describes each **item** in the array — the after-filter automatically unwraps arrays and validates each element individually.

```ruby
# Array of strings — e.g. ["key1", "key2", "key3"]
endpoint :get, '/v2/properties' do
  summary 'List property keys'
  response 200, items: :string
end

# Array of arrays (tuples) — e.g. [["value", 1], ["other", 2]]
endpoint :get, '/v2/properties/filtered/:key' do
  summary 'Property values with counts'
  response 200, items: :array
end
```

Supported types: `:string`, `:integer`, `:number`, `:boolean`, `:array`.

### Query Parameters

```ruby
endpoint :get, '/v2/widgets' do
  summary 'List widgets'

  query do
    string  :status, required: true, enum: %w[active archived], description: 'Filter by status'
    integer :page, nullable: true
    integer :per_page
  end

  response 200 do
    array :widgets, required: true do
      integer :id, required: true
      string  :name
    end
  end
end
```

### Security

A default security scheme can be set at the app level with `set :endpoint_security, :bearer`. Individual endpoints can override it:

```ruby
# Public endpoint — no auth required
endpoint :get, '/v2/health' do
  security :none
end
```

Supported schemes: `:bearer` (HTTP Bearer token). Use `:none` to mark an endpoint as public.

## Schema Builder DSL

The `body`, `query`, and `response` blocks use a builder DSL with these types. (For `response`, you can also pass `items:` directly — see [Primitive-Type Responses](#primitive-type-responses) above.)

| Method    | Options                                  |
|-----------|------------------------------------------|
| `string`  | `required:`, `enum:`, `nullable:`, `description:` |
| `integer` | `required:`, `enum:`, `nullable:`, `description:` |
| `number`  | `required:`, `enum:`, `nullable:`, `description:` |
| `boolean` | `required:`, `nullable:`, `description:`           |
| `array`   | `required:`, `nullable:`, `items:`, `description:`, block |
| `object`  | `required:`, `nullable:`, `description:`, block (optional) |

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

### Configuration Levels

Settings are resolved with **endpoint > controller > app-wide** precedence.

**App-wide** — sets the global default for all controllers:

```ruby
Sinatra::ExchangeSchema.request_validation  = :strict
Sinatra::ExchangeSchema.response_validation = :off
Sinatra::ExchangeSchema.missing_schema      = :warn
```

**Per-controller** — overrides the app-wide default for a single Sinatra class:

```ruby
class Api < Sinatra::Base
  register Sinatra::ExchangeSchema
  set :request_validation, :strict
end
```

**Per-endpoint** — overrides both app-wide and controller settings for one route:

```ruby
endpoint :post, '/v2/widgets' do
  request_validation :strict
  response_validation :off
  body do
    string :name, required: true
  end
end
```

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

The gem can generate an OpenAPI 3.0 YAML spec from your endpoint declarations.

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

### Programmatic

```ruby
require 'sinatra/exchange_schema'

declarations = MyApp::Controllers::Base.endpoint_declarations
doc = Sinatra::ExchangeSchema::OpenapiGenerator.call(
  declarations,
  info: { title: 'My API', version: 'v1' }
)
```

## Development

```bash
bundle install
bundle exec rspec
```
