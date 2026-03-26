require 'spec_helper'

describe Sinatra::ExchangeSchema::RequestValidator do
  let(:schema) do
    {
      'type' => 'object',
      'properties' => {
        'filter_ids' => { 'type' => 'array', 'items' => { 'type' => 'object' } },
      },
    }
  end

  describe '.call' do
    context 'with a valid payload' do
      it 'returns nil' do
        result = described_class.call({ 'filter_ids' => [{ 'id' => 1 }] }, schema)
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
        result = described_class.call({ 'filter_ids' => [569804] }, schema)
        expect(result).to be_an(Array)
        expect(result).not_to be_empty
        expect(result.first).to include(
          field: '/filter_ids/0',
          type: 'object',
          actual_value: 569804
        )
      end
    end
  end
end
