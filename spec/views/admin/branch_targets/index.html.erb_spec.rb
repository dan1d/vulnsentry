require "rails_helper"

RSpec.describe "admin/branch_targets/index", type: :view do
  it "renders filters and pagination nav" do
    branch = build_stubbed(:branch_target, name: "ruby_3_4", enabled: true, maintenance_status: "normal")

    request_obj = Pagy::Request.new(request: { base_url: "http://test.host", path: "/admin/branch_targets", params: {} })
    pagy = Pagy::Offset.new(count: 1, page: 1, limit: 50, request: request_obj)

    assign(:branch_targets, [ branch ])
    assign(:pagy, pagy)

    render

    expect(rendered).to include("Branch targets")
    expect(rendered).to include("Maintenance status")
    expect(rendered).to include("series-nav")
  end
end
