require "rails_helper"

RSpec.describe RubyLang::SecurityAnnouncementParser do
  it "extracts fixed version for a gem from ruby-lang advisory HTML" do
    html = <<~HTML
      <h1>CVE-2024-49761: ReDoS vulnerability in REXML</h1>
      <p>Please update REXML gem to version 3.3.9 or later.</p>
    HTML

    fixed = described_class.extract_fixed_version_for_gem(html: html, gem_name: "rexml")
    expect(fixed).to eq("3.3.9")
  end

  it "returns nil when not present" do
    html = "<html><body><p>No recommendation here.</p></body></html>"
    fixed = described_class.extract_fixed_version_for_gem(html: html, gem_name: "rexml")
    expect(fixed).to be_nil
  end
end
