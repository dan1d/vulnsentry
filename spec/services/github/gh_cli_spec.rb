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
end
