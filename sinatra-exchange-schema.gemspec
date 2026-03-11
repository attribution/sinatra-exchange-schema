require_relative 'lib/sinatra/exchange_schema/version'

Gem::Specification.new do |spec|
  spec.name = 'sinatra-exchange-schema'
  spec.version = Sinatra::ExchangeSchema::VERSION
  spec.authors = ['Attribution']
  spec.summary = 'Endpoint schema DSL, validation, and OpenAPI generation for Sinatra'
  spec.homepage = 'https://github.com/attribution/sinatra-exchange-schema'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.0'

  spec.files = Dir['lib/**/*.rb']
  spec.require_paths = ['lib']

  spec.add_dependency 'json_schemer', '~> 2.0'
  spec.add_dependency 'rack', '>= 2.0'
  spec.add_dependency 'sinatra', '>= 3.0'

  spec.add_development_dependency 'rack-test', '~> 2.0'
  spec.add_development_dependency 'rake', '>= 12.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
end
