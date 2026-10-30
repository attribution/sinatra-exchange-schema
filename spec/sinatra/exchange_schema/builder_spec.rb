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

  describe 'format' do
    before { builder.string :since, format: :date }

    it 'includes the format name' do
      expect(schema['properties']['since']).to eq('type' => 'string', 'format' => 'date')
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

  describe 'multi-type (same field declared twice)' do
    it 'merges two types' do
      builder.string :field
      builder.boolean :field
      expect(schema['properties']['field']).to eq('type' => %w[string boolean])
    end

    it 'preserves nullable from first declaration' do
      builder.string :field, nullable: true
      builder.boolean :field
      expect(schema['properties']['field']).to eq('type' => %w[string boolean null])
    end

    it 'adds nullable from second declaration' do
      builder.string :field
      builder.boolean :field, nullable: true
      expect(schema['properties']['field']).to eq('type' => %w[string boolean null])
    end

    it 'does not duplicate null' do
      builder.string :field, nullable: true
      builder.boolean :field, nullable: true
      expect(schema['properties']['field']['type'].count('null')).to eq 1
    end

    it 'does not duplicate required' do
      builder.string :field, required: true
      builder.boolean :field, required: true
      expect(schema['required']).to eq ['field']
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

  describe 'any' do
    it 'declares every JSON type' do
      builder.any :trait, description: 'As the client sent it'
      expect(builder.to_json_schema['properties']['trait']).to eq(
        'type' => %w[string integer number boolean object array null],
        'description' => 'As the client sent it'
      )
    end

    it 'tracks required' do
      builder.any :trait, required: true
      expect(builder.to_json_schema['required']).to eq ['trait']
    end
  end

  describe 'map' do
    it 'compiles scalar values from a symbol' do
      builder.map :totals, values: :integer
      expect(schema['properties']['totals']).to eq('type' => 'object', 'additionalProperties' => { 'type' => 'integer' })
    end

    it 'takes a schema hash as the values' do
      builder.map :tags, values: { 'type' => 'array', 'items' => { 'type' => 'string' } }
      expect(schema['properties']['tags']['additionalProperties']).to eq('type' => 'array', 'items' => { 'type' => 'string' })
    end

    it 'compiles the value object from a block' do
      builder.map :articles, required: true, description: 'Keyed by article id' do
        string  :name, required: true
        integer :views
      end

      articles = schema['properties']['articles']
      expect(articles['type']).to eq('object')
      expect(articles['description']).to eq('Keyed by article id')
      expect(articles['additionalProperties']).to eq(
        'type' => 'object',
        'properties' => { 'name' => { 'type' => 'string' }, 'views' => { 'type' => 'integer' } },
        'required' => ['name']
      )
      expect(schema['required']).to eq(['articles'])
    end

    it 'nests under an object and as another map\'s values' do
      builder.object :report do
        map :by_day, values: { 'type' => 'object', 'additionalProperties' => { 'type' => 'number' } }
      end

      by_day = schema['properties']['report']['properties']['by_day']
      expect(by_day['additionalProperties']['additionalProperties']).to eq('type' => 'number')
    end

    it 'produces a type array when nullable' do
      builder.map :totals, values: :integer, nullable: true
      expect(schema['properties']['totals']['type']).to eq(%w[object null])
    end

    it 'refuses a map without values' do
      expect { builder.map :totals }.to raise_error(ArgumentError, /needs values: or a block/)
    end
  end

  describe 'values' do
    it 'declares what every key not named takes, beside the named ones' do
      builder.object :total do
        integer :views
      end
      builder.values do
        integer :views
        integer :change
      end

      expect(schema['properties'].keys).to eq(['total'])
      expect(schema['additionalProperties']['properties'].keys).to eq(%w[views change])
    end

    it 'takes a type' do
      builder.values :integer
      expect(schema['additionalProperties']).to eq('type' => 'integer')
    end

    it 'takes a schema hash' do
      builder.values('type' => 'array', 'items' => { 'type' => 'string' })
      expect(schema['additionalProperties']).to eq('type' => 'array', 'items' => { 'type' => 'string' })
    end

    it 'works inside a map\'s value object' do
      builder.map :by_article do
        object(:total) { integer :views }
        values { integer :views }
      end

      value = schema['properties']['by_article']['additionalProperties']
      expect(value['properties'].keys).to eq(['total'])
      expect(value['additionalProperties']['properties'].keys).to eq(['views'])
    end

    it 'refuses values without a type, a schema or a block' do
      expect { builder.values }.to raise_error(ArgumentError, /needs a type/)
    end

    it 'is left out when never declared' do
      builder.string :name
      expect(schema).not_to have_key('additionalProperties')
    end
  end
end
