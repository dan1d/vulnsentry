require "rails_helper"

RSpec.describe Github::ForkBranchCleaner do
  it "deletes a branch via gh api" do
    gh = instance_double(Github::GhCli)
    allow(gh).to receive(:run!).and_return("")

    cleaner = described_class.new(gh: gh)
    result = cleaner.delete_branch(repo: "dan1d/ruby", branch: "bump-rexml-3.4.5-master")

    expect(result).to be(true)
    expect(gh).to have_received(:run!).with(
      "api",
      "--silent",
      "--method",
      "DELETE",
      "/repos/dan1d/ruby/git/refs/heads/bump-rexml-3.4.5-master"
    )
  end
end
