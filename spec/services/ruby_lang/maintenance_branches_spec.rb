require "rails_helper"

RSpec.describe RubyLang::MaintenanceBranches do
  it "parses non-EOL branches and normalizes statuses" do
    html = <<~HTML
      <h3>Ruby 3.4</h3>
      <p>status: normal maintenance</p>
      <h3>Ruby 3.2</h3>
      <p>status: security maintenance</p>
      <h3>Ruby 3.1</h3>
      <p>status: eol</p>
    HTML

    branches = described_class.new.parse_supported_html(html)
    expect(branches.map(&:series)).to contain_exactly("3.4", "3.2")
    expect(branches.find { |b| b.series == "3.4" }.status).to eq("normal")
    expect(branches.find { |b| b.series == "3.2" }.status).to eq("security")
  end
end
