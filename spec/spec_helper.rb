ENV['RACK_ENV'] = 'test'
require 'rspec'
require 'rack/test'
require 'sinatra/exchange_schema'

Sinatra::ExchangeSchema.request_validation = :strict
Sinatra::ExchangeSchema.response_validation = :strict
Sinatra::ExchangeSchema.missing_schema = :strict
