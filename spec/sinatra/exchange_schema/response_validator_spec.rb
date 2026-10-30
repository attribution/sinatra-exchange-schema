require 'spec_helper'

describe Sinatra::ExchangeSchema::ResponseValidator do
  let(:schema) do
    {
      'type' => 'object',
      'properties' => {
        'id' => { 'type' => 'string' },
        'name' => { 'type' => 'string' },
      },
      'required' => ['id'],
    }
  end

  describe '.call' do
    context 'with a valid payload' do
      it 'returns nil' do
        result = described_class.call({ 'id' => '1', 'name' => 'test' }, schema)
        expect(result).to be_nil
      end
    end

    context 'with nil schema' do
      it 'returns nil' do
        result = described_class.call({ 'bad' => true }, nil)
        expect(result).to be_nil
      end
    end

    context 'with an invalid payload' do
      it 'returns an array of formatted errors with actual_value' do
        result = described_class.call({ 'name' => 'test' }, schema)
        expect(result).to be_an(Array)
        expect(result).not_to be_empty
        expect(result.first).to include(:field, :error, :type, :actual_value)
      end
    end

    context 'with a map' do
      let(:schema) do
        builder = Sinatra::ExchangeSchema::Builder.new
        builder.map(:articles) { integer :views, required: true }
        builder.to_json_schema
      end

      it 'passes a payload with any keys whose values fit' do
        expect(described_class.call({ 'articles' => { '17' => { 'views' => 3 }, '42' => { 'views' => 9 } } }, schema)).to be_nil
      end

      it 'fails the one wrong value, naming its key' do
        result = described_class.call({ 'articles' => { '17' => { 'views' => 3 }, '42' => { 'views' => 'nine' } } }, schema)
        expect(result.map { |err| err[:field] }).to eq(['/articles/42/views'])
      end
    end

    context 'with named keys beside values' do
      let(:schema) do
        builder = Sinatra::ExchangeSchema::Builder.new
        builder.map(:by_article) do
          object(:total, required: true) { integer :views, required: true }
          values do
            integer :views, required: true
            integer :change, required: true
          end
        end
        builder.to_json_schema
      end

      let(:payload) do
        { 'by_article' => { '7' => { 'total' => { 'views' => 12 }, 'p1' => { 'views' => 5, 'change' => 0 }, 'p2' => { 'views' => 7, 'change' => 2 } } } }
      end

      it 'passes the named key under its own schema and the others under values' do
        expect(described_class.call(payload, schema)).to be_nil
      end

      it 'fails a period that misses what values require, naming it' do
        payload['by_article']['7']['p2'] = { 'views' => 7 }
        expect(described_class.call(payload, schema).map { |err| err[:field] }).to eq(['/by_article/7/p2'])
      end

      it 'fails the named key under its own schema, not the values one' do
        payload['by_article']['7']['total'] = { 'views' => 'twelve' }
        expect(described_class.call(payload, schema).map { |err| err[:field] }).to eq(['/by_article/7/total/views'])
      end
    end
  end
end
