require "rails_helper"

RSpec.describe Github::PullRequestStatusFetcher do
  it "maps open PR state" do
    gh = instance_double(Github::GhCli)
    allow(gh).to receive(:json!).and_return(
      "state" => "open",
      "created_at" => "2026-01-25T10:00:00Z",
      "closed_at" => nil,
      "merged_at" => nil,
      "body" => nil,
      "labels" => []
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
      "merged_at" => "2026-01-25T10:30:00Z",
      "body" => nil,
      "labels" => []
    )

    data = described_class.new(gh: gh).fetch(upstream_repo: "ruby/ruby", pr_number: 123)
    expect(data[:status]).to eq("merged")
  end

  it "extracts body from PR data" do
    gh = instance_double(Github::GhCli)
    allow(gh).to receive(:json!).and_return(
      "state" => "open",
      "created_at" => "2026-01-25T10:00:00Z",
      "closed_at" => nil,
      "merged_at" => nil,
      "body" => "## Summary\nSecurity bump for bundled gem.",
      "labels" => []
    )

    data = described_class.new(gh: gh).fetch(upstream_repo: "ruby/ruby", pr_number: 123)
    expect(data[:body]).to eq("## Summary\nSecurity bump for bundled gem.")
  end

  it "extracts label names from PR data" do
    gh = instance_double(Github::GhCli)
    allow(gh).to receive(:json!).and_return(
      "state" => "open",
      "created_at" => "2026-01-25T10:00:00Z",
      "closed_at" => nil,
      "merged_at" => nil,
      "body" => nil,
      "labels" => [
        { "name" => "Backport", "color" => "E6FA62" },
        { "name" => "Security", "color" => "FF0000" }
      ]
    )

    data = described_class.new(gh: gh).fetch(upstream_repo: "ruby/ruby", pr_number: 123)
    expect(data[:labels]).to eq(%w[Backport Security])
  end

  it "returns empty labels array when labels is nil" do
    gh = instance_double(Github::GhCli)
    allow(gh).to receive(:json!).and_return(
      "state" => "open",
      "created_at" => "2026-01-25T10:00:00Z",
      "closed_at" => nil,
      "merged_at" => nil,
      "body" => nil,
      "labels" => nil
    )

    data = described_class.new(gh: gh).fetch(upstream_repo: "ruby/ruby", pr_number: 123)
    expect(data[:labels]).to eq([])
  end
end
