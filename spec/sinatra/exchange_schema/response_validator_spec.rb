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
      it 'returns an array of formatted errors' do
        result = described_class.call({ 'name' => 'test' }, schema)
        expect(result).to be_an(Array)
        expect(result).not_to be_empty
        expect(result.first).to have_key(:field)
        expect(result.first).to have_key(:error)
        expect(result.first).to have_key(:type)
      end
    end
  end
end
