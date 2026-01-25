require "rails_helper"

RSpec.describe Github::PullRequestStatusFetcher do
  it "maps open PR state" do
    gh = instance_double(Github::GhCli)
    allow(gh).to receive(:json!).and_return(
      "state" => "open",
      "created_at" => "2026-01-25T10:00:00Z",
      "closed_at" => nil,
      "merged_at" => nil
    )

    data = described_class.new(gh: gh).fetch(upstream_repo: "ruby/ruby", pr_number: 123)
    expect(data[:status]).to eq("open")
  end

  it "maps merged PR state" do
    gh = instance_double(Github::GhCli)
    allow(gh).to receive(:json!).and_return(
      "state" => "closed",
      "created_at" => "2026-01-25T10:00:00Z",
      "closed_at" => "2026-01-25T11:00:00Z",
      "merged_at" => "2026-01-25T10:30:00Z"
    )

    data = described_class.new(gh: gh).fetch(upstream_repo: "ruby/ruby", pr_number: 123)
    expect(data[:status]).to eq("merged")
  end
end
