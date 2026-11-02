require 'spec_helper'

describe Sinatra::ExchangeSchema::Schemas do
  after do
    described_class.clear
  end

  describe '.define' do
    it 'takes the same name again with the same shape, and refuses another shape' do
      described_class.define(:Row) { integer :views }
      expect { described_class.define(:Row) { integer :views } }.not_to raise_error
      expect { described_class.define(:Row) { string :views } }.to raise_error(ArgumentError, /"Row" is already defined/)
      expect(described_class.fetch(:Row)['properties']['views']).to eq('type' => 'integer')
    end

    it 'refuses a name that is not a component key' do
      expect { described_class.define(:'Article/V1') { string :name } }.to raise_error(ArgumentError, /letters, digits/)
      expect { described_class.define('Article.V1-draft_2') { string :name } }.not_to raise_error
    end
  end

  describe '.referenced' do
    it 'leaves data alone: a hash under enum, const, default or examples is not a reference' do
      schema = {
        'type' => 'object',
        'properties' => {
          'kind' => { 'type' => 'object', 'enum' => [{ '$ref' => '#/components/schemas/Nope' }], 'default' => { '$ref' => '#/components/schemas/Nope' } }
        },
        'examples' => [{ '$ref' => '#/components/schemas/Nope' }]
      }
      expect(described_class.referenced(schema)).to eq []
      expect(described_class.resolve(schema)).to equal schema
    end

    it 'reads a property named like a data keyword as a name, and finds the reference under it' do
      described_class.define(:Row) { integer :views }
      schema = { 'type' => 'object', 'properties' => { 'default' => { '$ref' => '#/components/schemas/Row' }, 'enum' => { 'type' => 'string', 'enum' => %w[a b] } } }
      expect(described_class.referenced(schema)).to eq ['Row']
    end

    it 'follows references transitively, each once' do
      described_class.define(:Row) { integer :views }
      described_class.define(:Totals) { object :total, ref: :Row; array :rows, items: ref(:Row) }
      expect(described_class.referenced({ 'allOf' => [{ '$ref' => '#/components/schemas/Totals' }] })).to eq %w[Totals Row]
    end
  end

  describe '.flatten' do
    it 'leaves a pointer into another document alone' do
      schema = { 'type' => 'array', 'items' => { '$ref' => '#/items/$defs/Row' } }
      expect(described_class.flatten(schema)).to equal schema
      expect(described_class.flatten(schema['items'])).to equal schema['items']
    end

    it 'follows a reference and merges allOf members, properties and required alike' do
      described_class.define(:Row) { integer :views, required: true }
      composed = { 'allOf' => [{ '$ref' => '#/components/schemas/Row' }, { 'type' => 'object', 'properties' => { 'label' => { 'type' => 'string' } }, 'required' => ['label'] }], 'description' => 'A row' }
      flat = described_class.flatten(composed)
      expect(flat['properties'].keys).to eq %w[views label]
      expect(flat['required']).to eq %w[views label]
      expect(flat['description']).to eq 'A row'
    end
  end
end
