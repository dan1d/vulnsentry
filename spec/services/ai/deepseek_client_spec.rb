require "rails_helper"

RSpec.describe Ai::DeepseekClient do
  let(:success_response) do
    {
      "choices" => [
        { "message" => { "content" => '{"result":"success"}' } }
      ],
      "usage" => {
        "prompt_tokens" => 100,
        "completion_tokens" => 50,
        "total_tokens" => 150
      }
    }
  end

  describe "#enabled?" do
    it "returns false when API key is missing" do
      client = described_class.new(api_key: nil)
      expect(client.enabled?).to be(false)
    end

    it "returns true when API key is present" do
      client = described_class.new(api_key: "test-key")
      expect(client.enabled?).to be(true)
    end
  end

  describe "#extract_json!" do
    context "when API key is missing" do
      it "raises with helpful error message" do
        client = described_class.new(api_key: nil)
        expect do
          client.extract_json!(system: "x", user: "y")
        end.to raise_error(Ai::DeepseekClient::Error, /DEEPSEEK_API_KEY not set.*configure/i)
      end
    end

    context "with successful response" do
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

      it "sends temperature parameter in request" do
        stub_request(:post, Ai::DeepseekClient::DEFAULT_URL)
          .with(body: hash_including("temperature" => 0.5))
          .to_return(
            status: 200,
            headers: { "Content-Type" => "application/json" },
            body: success_response.to_json
          )

        client = described_class.new(api_key: "test", temperature: 0.5)
        client.extract_json!(system: "x", user: "y")
      end

      it "uses default temperature of 0.1" do
        stub_request(:post, Ai::DeepseekClient::DEFAULT_URL)
          .with(body: hash_including("temperature" => 0.1))
          .to_return(
            status: 200,
            headers: { "Content-Type" => "application/json" },
            body: success_response.to_json
          )

        client = described_class.new(api_key: "test")
        client.extract_json!(system: "x", user: "y")
      end

      it "logs request to SystemEvent" do
        stub_request(:post, Ai::DeepseekClient::DEFAULT_URL)
          .to_return(
            status: 200,
            headers: { "Content-Type" => "application/json" },
            body: success_response.to_json
          )

        client = described_class.new(api_key: "test")

        expect { client.extract_json!(system: "test system", user: "test user") }
          .to change { SystemEvent.where(kind: "deepseek_request").count }.by(1)
          .and change { SystemEvent.where(kind: "deepseek_response").count }.by(1)
      end
    end

    context "with markdown fences" do
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

    context "with retry logic" do
      it "retries on network timeout and succeeds" do
        call_count = 0
        stub_request(:post, Ai::DeepseekClient::DEFAULT_URL)
          .to_return do |_request|
            call_count += 1
            if call_count < 2
              raise Net::ReadTimeout
            else
              {
                status: 200,
                headers: { "Content-Type" => "application/json" },
                body: success_response.to_json
              }
            end
          end

        client = described_class.new(api_key: "test", max_retries: 3)
        result = client.extract_json!(system: "x", user: "y")

        expect(result).to eq({ "result" => "success" })
        expect(call_count).to eq(2)
      end

      it "retries on rate limit (429) and succeeds" do
        call_count = 0
        stub_request(:post, Ai::DeepseekClient::DEFAULT_URL)
          .to_return do |_request|
            call_count += 1
            if call_count < 2
              { status: 429, body: '{"error":"rate limited"}' }
            else
              {
                status: 200,
                headers: { "Content-Type" => "application/json" },
                body: success_response.to_json
              }
            end
          end

        client = described_class.new(api_key: "test", max_retries: 3)
        result = client.extract_json!(system: "x", user: "y")

        expect(result).to eq({ "result" => "success" })
        expect(call_count).to eq(2)
      end

      it "raises after max retries exhausted" do
        stub_request(:post, Ai::DeepseekClient::DEFAULT_URL)
          .to_raise(Net::ReadTimeout)

        client = described_class.new(api_key: "test", max_retries: 2)

        expect { client.extract_json!(system: "x", user: "y") }
          .to raise_error(Ai::DeepseekClient::Error, /failed after 2 attempts/i)
      end

      it "logs retry attempts to SystemEvent" do
        call_count = 0
        stub_request(:post, Ai::DeepseekClient::DEFAULT_URL)
          .to_return do |_request|
            call_count += 1
            if call_count < 2
              raise Net::ReadTimeout
            else
              {
                status: 200,
                headers: { "Content-Type" => "application/json" },
                body: success_response.to_json
              }
            end
          end

        client = described_class.new(api_key: "test", max_retries: 3)

        expect { client.extract_json!(system: "x", user: "y") }
          .to change { SystemEvent.where(kind: "deepseek_retry").count }.by(1)
      end

      it "does not retry on authentication errors (401)" do
        stub_request(:post, Ai::DeepseekClient::DEFAULT_URL)
          .to_return(status: 401, body: '{"error":"unauthorized"}')

        client = described_class.new(api_key: "test", max_retries: 3)

        expect { client.extract_json!(system: "x", user: "y") }
          .to raise_error(Ai::DeepseekClient::Error, /authentication failed.*API key/i)

        expect(a_request(:post, Ai::DeepseekClient::DEFAULT_URL)).to have_been_made.once
      end
    end

    context "with HTTP errors" do
      it "raises clear error on 500 server error" do
        stub_request(:post, Ai::DeepseekClient::DEFAULT_URL)
          .to_return(status: 500, body: "Internal Server Error")

        client = described_class.new(api_key: "test", max_retries: 1)

        expect { client.extract_json!(system: "x", user: "y") }
          .to raise_error(Ai::DeepseekClient::Error, /server error.*500/i)
      end

      it "raises clear error on 400 bad request with message" do
        stub_request(:post, Ai::DeepseekClient::DEFAULT_URL)
          .to_return(
            status: 400,
            body: '{"error":{"message":"Invalid model specified"}}'
          )

        client = described_class.new(api_key: "test")

        expect { client.extract_json!(system: "x", user: "y") }
          .to raise_error(Ai::DeepseekClient::Error, /bad request.*Invalid model/i)
      end

      it "raises clear error on 403 forbidden" do
        stub_request(:post, Ai::DeepseekClient::DEFAULT_URL)
          .to_return(status: 403, body: '{"error":"forbidden"}')

        client = described_class.new(api_key: "test")

        expect { client.extract_json!(system: "x", user: "y") }
          .to raise_error(Ai::DeepseekClient::Error, /forbidden.*permissions/i)
      end
    end

    context "with invalid response content" do
      it "raises when response is missing content" do
        stub_request(:post, Ai::DeepseekClient::DEFAULT_URL)
          .to_return(
            status: 200,
            headers: { "Content-Type" => "application/json" },
            body: { "choices" => [ { "message" => {} } ] }.to_json
          )

        client = described_class.new(api_key: "test")

        expect { client.extract_json!(system: "x", user: "y") }
          .to raise_error(Ai::DeepseekClient::Error, /missing content/i)
      end

      it "raises with truncated content when JSON is invalid" do
        stub_request(:post, Ai::DeepseekClient::DEFAULT_URL)
          .to_return(
            status: 200,
            headers: { "Content-Type" => "application/json" },
            body: {
              "choices" => [
                { "message" => { "content" => "not valid json" } }
              ]
            }.to_json
          )

        client = described_class.new(api_key: "test")

        expect { client.extract_json!(system: "x", user: "y") }
          .to raise_error(Ai::DeepseekClient::Error, /invalid JSON.*Raw content/i)
      end
    end

    context "with error logging" do
      it "logs failed requests to SystemEvent" do
        stub_request(:post, Ai::DeepseekClient::DEFAULT_URL)
          .to_return(status: 401, body: '{"error":"unauthorized"}')

        client = described_class.new(api_key: "test")

        expect {
          client.extract_json!(system: "x", user: "y") rescue nil
        }.to change { SystemEvent.where(kind: "deepseek_error").count }.by(1)

        event = SystemEvent.where(kind: "deepseek_error").last
        expect(event.status).to eq("failed")
        expect(event.payload["retryable"]).to eq(false)
      end
    end
  end
end
