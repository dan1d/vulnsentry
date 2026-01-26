require "rails_helper"

RSpec.describe "admin/advisories/index", type: :view do
  it "renders filters and pagination" do
    advisory = build_stubbed(:advisory, fingerprint: "osv:OSV-1", source: "osv", gem_name: "rexml")

    request_obj = Pagy::Request.new(
      request: { base_url: "http://test.host", path: "/admin/advisories", params: {} }
    )
    pagy = Pagy::Offset.new(count: 1, page: 1, limit: 50, request: request_obj)

    assign(:advisories, [ advisory ])
    assign(:pagy, pagy)

    render

    expect(rendered).to include("Advisories")
    expect(rendered).to include("Search")
    expect(rendered).to include("series-nav")
  end
end
