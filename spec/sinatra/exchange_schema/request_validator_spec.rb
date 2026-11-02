require 'spec_helper'

describe Sinatra::ExchangeSchema::RequestValidator do
  context 'through a named schema' do
    before do
      Sinatra::ExchangeSchema.schema(:Article) { string :name, required: true }
    end

    after do
      Sinatra::ExchangeSchema::Schemas.clear
    end

    let(:schema) do
      decl = Sinatra::ExchangeSchema::EndpointDeclaration.new(:post, '/articles')
      decl.body(ref: :Article) { string :note }
      decl.close_body!
      decl.body_schema
    end

    it 'passes what the named schema and the extension declare' do
      expect(described_class.call({ 'name' => 'One', 'note' => 'n' }, schema)).to be_nil
    end

    # a field that fails inside the reference is reported twice, by the reference and, its
    # annotations dropped with the failure, as unevaluated: both name the field
    it 'fails under the named schema, naming the field' do
      expect(described_class.call({ 'name' => 1, 'note' => 'n' }, schema).map { |err| err[:field] }.uniq).to eq(['/name'])
    end

    it 'rejects a key neither declared, the body being closed as one' do
      errors = described_class.call({ 'name' => 'One', 'nope' => true }, schema)
      expect(errors.map { |err| err[:field] }).to eq(['/nope'])
    end
  end

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

    context 'with a format on a property' do
      let(:schema) do
        { 'type' => 'object', 'properties' => { 'since' => { 'type' => 'string', 'format' => 'date' } } }
      end

      it 'accepts a value in that format' do
        expect(described_class.call({ 'since' => '2026-10-11' }, schema)).to be_nil
      end

      it 'rejects a value outside it, naming the field' do
        result = described_class.call({ 'since' => '2026-13-01' }, schema)
        expect(result.first).to include(field: '/since', type: 'format')
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
