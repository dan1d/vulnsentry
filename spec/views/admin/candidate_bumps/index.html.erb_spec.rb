require "rails_helper"

RSpec.describe "admin/candidate_bumps/index", type: :view do
  it "renders filters and pagination nav" do
    candidate = build_stubbed(
      :candidate_bump,
      base_branch: "master",
      gem_name: "rexml",
      current_version: "3.4.4",
      target_version: "3.4.5",
      state: "ready_for_review"
    )

    request_obj = Pagy::Request.new(request: { base_url: "http://test.host", path: "/admin/candidate_bumps", params: {} })
    pagy = Pagy::Offset.new(count: 1, page: 1, limit: 50, request: request_obj)

    assign(:candidate_bumps, [ candidate ])
    assign(:pagy, pagy)

    render

    expect(rendered).to include("Candidate bumps")
    expect(rendered).to include("Filter")
    expect(rendered).to include("series-nav")
  end
end
