require 'rails_helper'

RSpec.describe Captain::LlmService do
  let(:api_key) { 'test-gemini-key' }
  let(:model) { 'gemini-2.5-flash' }
  let(:service) { described_class.new(provider: 'gemini', api_key: api_key, model: model) }

  describe '#call (Gemini)' do
    let(:messages) do
      [
        { role: 'system', content: 'You are Captain AI.' },
        { role: 'user', content: 'Say hello' }
      ]
    end

    before do
      # Stub Net::HTTP to simulate Gemini response
      stub_request(:post, /generativelanguage.googleapis.com/)
        .to_return(status: 200, body: {
          candidates: [
            {
              content: {
                parts: [ { text: { result: 'Hello', stop: true }.to_json } ]
              }
            }
          ]
        }.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'returns parsed result from Gemini response' do
      result = service.call(messages)
      expect(result[:output]).to eq('Hello')
      expect(result[:stop]).to be(true)
    end
  end
end
