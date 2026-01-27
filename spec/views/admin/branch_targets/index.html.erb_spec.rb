require "rails_helper"

RSpec.describe "admin/branch_targets/index", type: :view do
  it "renders filters and pagination nav" do
    branch = build_stubbed(:branch_target, name: "ruby_3_4", enabled: true, maintenance_status: "normal")

    assign(:branch_targets, Kaminari.paginate_array([ branch ]).page(1).per(50))

    render

    expect(rendered).to include("Branch targets")
    expect(rendered).to include("Maintenance status")
    expect(rendered).to include("Per page")
  end
end
