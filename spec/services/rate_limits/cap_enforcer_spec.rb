require "rails_helper"

RSpec.describe RateLimits::CapEnforcer do
  let(:now) { Time.zone.parse("2026-01-25 12:00:00") }

  before do
    BotConfig.delete_all
    create(
      :bot_config,
      global_daily_cap: 3,
      global_hourly_cap: 1,
      per_branch_daily_cap: 1,
      per_gem_daily_cap: 1,
      rejection_cooldown_hours: 24
    )
  end

  it "allows when under all caps" do
    result = described_class.new(now: now).check!(gem_name: "rexml", base_branch: "ruby_3_4")
    expect(result.allowed).to be(true)
  end

  it "blocks when hourly cap is reached" do
    cb = create(:candidate_bump, gem_name: "rexml", base_branch: "ruby_3_4")
    create(:pull_request, candidate_bump: cb, created_at: now - 10.minutes)

    result = described_class.new(now: now).check!(gem_name: "net-imap", base_branch: "ruby_3_4")
    expect(result.allowed).to be(false)
    expect(result.reason).to eq("global_hourly_cap")
  end

  it "blocks when per-branch cap is reached" do
    cb = create(:candidate_bump, gem_name: "rexml", base_branch: "ruby_3_4")
    create(:pull_request, candidate_bump: cb, created_at: now - 2.hours)

    # Hourly cap is also 1 but this is outside the hour window.
    result = described_class.new(now: now).check!(gem_name: "net-imap", base_branch: "ruby_3_4")
    expect(result.allowed).to be(false)
    expect(result.reason).to eq("per_branch_daily_cap")
  end

  it "blocks when per-gem cap is reached" do
    cb = create(:candidate_bump, gem_name: "rexml", base_branch: "ruby_3_3")
    create(:pull_request, candidate_bump: cb, created_at: now - 2.hours)

    result = described_class.new(now: now).check!(gem_name: "rexml", base_branch: "ruby_3_4")
    expect(result.allowed).to be(false)
    expect(result.reason).to eq("per_gem_daily_cap")
  end

  it "blocks during rejection cooldown" do
    create(:candidate_bump, gem_name: "rexml", base_branch: "ruby_3_4", state: "rejected", updated_at: now - 1.hour)

    result = described_class.new(now: now).check!(gem_name: "rexml", base_branch: "ruby_3_4")
    expect(result.allowed).to be(false)
    expect(result.reason).to eq("cooldown")
    expect(result.next_eligible_at).to be > now
  end
end
