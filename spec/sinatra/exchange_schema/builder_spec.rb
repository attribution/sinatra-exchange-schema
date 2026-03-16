require 'spec_helper'

describe Sinatra::ExchangeSchema::Builder do
  subject(:schema) { builder.to_json_schema }

  let(:builder) { described_class.new }

  describe 'simple types' do
    before do
      builder.string :name, required: true
      builder.integer :count
      builder.number :score
      builder.boolean :active
    end

    it 'compiles properties with correct types' do
      expect(schema['properties']).to eq(
        'name' => { 'type' => 'string' },
        'count' => { 'type' => 'integer' },
        'score' => { 'type' => 'number' },
        'active' => { 'type' => 'boolean' }
      )
    end

    it 'tracks required fields' do
      expect(schema['required']).to eq(['name'])
    end

    it 'sets type to object' do
      expect(schema['type']).to eq('object')
    end
  end

  describe 'enum' do
    before { builder.string :status, enum: %w[active inactive] }

    it 'includes enum values' do
      expect(schema['properties']['status']).to eq(
        'type' => 'string', 'enum' => %w[active inactive]
      )
    end
  end

  describe 'no required fields' do
    before { builder.string :name }

    it 'omits required key' do
      expect(schema).not_to have_key('required')
    end
  end

  describe 'array type' do
    it 'compiles a simple array with symbol items' do
      builder.array :tags, items: :string
      expect(schema['properties']['tags']).to eq(
        'type' => 'array', 'items' => { 'type' => 'string' }
      )
    end

    it 'accepts a hash for items (backward compat)' do
      builder.array :ids, items: { 'type' => 'integer' }
      expect(schema['properties']['ids']).to eq(
        'type' => 'array', 'items' => { 'type' => 'integer' }
      )
    end

    it 'compiles an array with nested object' do
      builder.array :items do
        string :id, required: true
      end

      items_schema = schema['properties']['items']['items']
      expect(items_schema['type']).to eq('object')
      expect(items_schema['properties']['id']).to eq('type' => 'string')
      expect(items_schema['required']).to eq(['id'])
    end
  end

  describe 'nullable' do
    it 'produces a type array for a scalar field' do
      builder.string :name, nullable: true
      expect(schema['properties']['name']).to eq('type' => ['string', 'null'])
    end

    it 'produces a type array for an array field' do
      builder.array :tags, nullable: true
      expect(schema['properties']['tags']).to eq('type' => ['array', 'null'])
    end

    it 'combines required and nullable' do
      builder.string :name, required: true, nullable: true
      expect(schema['properties']['name']).to eq('type' => ['string', 'null'])
      expect(schema['required']).to eq(['name'])
    end
  end

  describe 'description' do
    it 'includes description on a scalar field' do
      builder.string :name, description: 'Full name of the user'
      expect(schema['properties']['name']).to eq(
        'type' => 'string', 'description' => 'Full name of the user'
      )
    end

    it 'includes description on an array field' do
      builder.array :tags, items: :string, description: 'List of tags'
      expect(schema['properties']['tags']).to eq(
        'type' => 'array', 'items' => { 'type' => 'string' }, 'description' => 'List of tags'
      )
    end

    it 'includes description on an object field' do
      builder.object :address, description: 'Mailing address' do
        string :city
      end
      addr = schema['properties']['address']
      expect(addr['description']).to eq('Mailing address')
      expect(addr['type']).to eq('object')
    end

    it 'omits description when not provided' do
      builder.string :name
      expect(schema['properties']['name']).not_to have_key('description')
    end
  end

  describe 'nested object' do
    before do
      builder.object :address, required: true do
        string :city, required: true
        string :zip
      end
    end

    it 'compiles nested object schema' do
      addr = schema['properties']['address']
      expect(addr['type']).to eq('object')
      expect(addr['properties']['city']).to eq('type' => 'string')
      expect(addr['properties']['zip']).to eq('type' => 'string')
      expect(addr['required']).to eq(['city'])
    end

    it 'marks parent as required' do
      expect(schema['required']).to eq(['address'])
    end

    it 'compiles an opaque object without a block' do
      builder.object :metadata
      expect(schema['properties']['metadata']).to eq('type' => 'object')
    end

    it 'compiles a nullable opaque object' do
      builder.object :metadata, nullable: true
      expect(schema['properties']['metadata']).to eq('type' => %w[object null])
    end
  end
end
