require "rails_helper"

RSpec.describe Ai::DeepseekClient do
  it "raises when API key is missing" do
    client = described_class.new(api_key: nil)
    expect(client.enabled?).to be(false)
    expect do
      client.extract_json!(system: "x", user: "y")
    end.to raise_error(Ai::DeepseekClient::Error, /DEEPSEEK_API_KEY/i)
  end

  it "parses JSON content from DeepSeek response" do
    stub_request(:post, Ai::DeepseekClient::DEFAULT_URL)
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          "choices" => [
            { "message" => { "content" => '[{"series":"3.4","status":"normal"}]' } }
          ]
        }.to_json
      )

    client = described_class.new(api_key: "test", url: Ai::DeepseekClient::DEFAULT_URL)
    json = client.extract_json!(system: "x", user: "y")
    expect(json).to eq([ { "series" => "3.4", "status" => "normal" } ])
  end

  it "strips markdown code fences from JSON response" do
    fenced_content = "```json\n[{\"series\":\"3.4\",\"status\":\"normal\"}]\n```"

    stub_request(:post, Ai::DeepseekClient::DEFAULT_URL)
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          "choices" => [
            { "message" => { "content" => fenced_content } }
          ]
        }.to_json
      )

    client = described_class.new(api_key: "test", url: Ai::DeepseekClient::DEFAULT_URL)
    json = client.extract_json!(system: "x", user: "y")
    expect(json).to eq([ { "series" => "3.4", "status" => "normal" } ])
  end

  it "strips plain markdown fences without language tag" do
    fenced_content = "```\n{\"key\":\"value\"}\n```"

    stub_request(:post, Ai::DeepseekClient::DEFAULT_URL)
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          "choices" => [
            { "message" => { "content" => fenced_content } }
          ]
        }.to_json
      )

    client = described_class.new(api_key: "test", url: Ai::DeepseekClient::DEFAULT_URL)
    json = client.extract_json!(system: "x", user: "y")
    expect(json).to eq({ "key" => "value" })
  end
end
