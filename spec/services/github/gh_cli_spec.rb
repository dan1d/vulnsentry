require "rails_helper"

RSpec.describe Github::GhCli do
  it "raises a structured error when gh fails" do
    cli = described_class.new(env: { "PATH" => "" })

    expect do
      cli.run!("--version")
    end.to raise_error(Github::GhCli::CommandError)
  end

  it "raises a structured error when gh returns invalid JSON" do
    status = instance_double(Process::Status, success?: true, exitstatus: 0)
    allow(Open3).to receive(:capture3).and_return([ "", "transient error", status ])

    cli = described_class.new(env: { "GH_TOKEN" => "test" })

    expect do
      cli.json!("api", "/repos/ruby/ruby/pulls/123")
    end.to raise_error(Github::GhCli::CommandError, /invalid JSON/)
  end

  describe "#paginated_json!" do
    it "parses NDJSON output from paginated API calls" do
      ndjson_output = "{\"id\":1,\"name\":\"first\"}\n{\"id\":2,\"name\":\"second\"}\n"
      status = instance_double(Process::Status, success?: true, exitstatus: 0)
      allow(Open3).to receive(:capture3).and_return([ ndjson_output, "", status ])

      cli = described_class.new(env: { "GH_TOKEN" => "test" })
      result = cli.paginated_json!("/repos/ruby/ruby/issues/123/comments")

      expect(result).to eq([
        { "id" => 1, "name" => "first" },
        { "id" => 2, "name" => "second" }
      ])
    end

    it "returns an empty array when there are no results" do
      status = instance_double(Process::Status, success?: true, exitstatus: 0)
      allow(Open3).to receive(:capture3).and_return([ "", "", status ])

      cli = described_class.new(env: { "GH_TOKEN" => "test" })
      result = cli.paginated_json!("/repos/ruby/ruby/issues/123/comments")

      expect(result).to eq([])
    end

    it "raises an error when the command fails" do
      status = instance_double(Process::Status, success?: false, exitstatus: 1)
      allow(Open3).to receive(:capture3).and_return([ "", "not found", status ])

      cli = described_class.new(env: { "GH_TOKEN" => "test" })

      expect do
        cli.paginated_json!("/repos/ruby/ruby/issues/999/comments")
      end.to raise_error(Github::GhCli::CommandError)
    end
  end
end
