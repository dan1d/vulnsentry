require "rails_helper"

RSpec.describe RubyLang::MaintenanceBranches do
  it "parses non-EOL branches and normalizes statuses" do
    html = <<~HTML
      ### Ruby 3.4
      status: normal maintenance
      ### Ruby 3.2
      status: security maintenance
      ### Ruby 3.1
      status: eol
    HTML

    branches = described_class.new.parse_supported(html)
    expect(branches.map(&:series)).to contain_exactly("3.4", "3.2")
    expect(branches.find { |b| b.series == "3.4" }.status).to eq("normal")
    expect(branches.find { |b| b.series == "3.2" }.status).to eq("security")
  end
end

