require "rails_helper"

RSpec.describe "admin/advisories/index", type: :view do
  it "renders filters and pagination" do
    advisory = build_stubbed(:advisory, fingerprint: "osv:OSV-1", source: "osv", gem_name: "rexml")

    assign(:advisories, Kaminari.paginate_array([ advisory ]).page(1).per(50))

    render

    expect(rendered).to include("Advisories")
    expect(rendered).to include("Search")
    expect(rendered).to include("Per page")
  end
end
