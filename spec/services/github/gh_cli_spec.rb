require "rails_helper"

RSpec.describe Github::GhCli do
  it "raises a structured error when gh fails" do
    cli = described_class.new(env: { "PATH" => "" })

    expect do
      cli.run!("--version")
    end.to raise_error(Github::GhCli::CommandError)
  end
end
