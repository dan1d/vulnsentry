require "rails_helper"

RSpec.describe RubyLang::MaintenanceBranches do
  it "parses branches and normalizes statuses" do
    html = <<~HTML
      <h3>Ruby 3.4</h3>
      <p>status: normal maintenance<br />
      release date: 2024-12-25<br />
      normal maintenance until: TBD<br />
      EOL: TBD</p>
      <h3>Ruby 3.2</h3>
      <p>status: security maintenance<br />
      release date: 2022-12-25<br />
      normal maintenance until: 2025-04-01<br />
      EOL: 2026-03-31 (expected)</p>
      <h3>Ruby 3.1</h3>
      <p>status: eol<br />
      release date: 2021-12-25<br />
      normal maintenance until: 2024-04-01<br />
      EOL: 2025-03-26</p>
      <h3>Ruby 2.0.0</h3>
      <p>status: eol<br />
      release date: 2013-02-24<br />
      normal maintenance until: 2016-02-24<br />
      EOL: 2016-02-24</p>
    HTML

    branches = described_class.new.parse_all_html(html)
    expect(branches.map(&:series)).to contain_exactly("3.4", "3.2", "3.1", "2.0.0")
    expect(branches.find { |b| b.series == "3.4" }.status).to eq("normal")
    expect(branches.find { |b| b.series == "3.2" }.status).to eq("security")
    expect(branches.find { |b| b.series == "3.1" }.status).to eq("eol")
    expect(branches.find { |b| b.series == "2.0.0" }.status).to eq("eol")
  end
end
