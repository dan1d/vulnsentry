require "rails_helper"

RSpec.describe "admin/advisories/show", type: :view do
  it "renders fingerprint and raw payload" do
    advisory = build_stubbed(:advisory, fingerprint: "osv:OSV-1", raw: { "k" => "v" })
    assign(:advisory, advisory)
    render
    expect(rendered).to include("osv:OSV-1")
    expect(rendered).to include("&quot;k&quot;")
  end
end
