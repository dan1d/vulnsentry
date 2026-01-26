require "rails_helper"

RSpec.describe "admin/pull_requests/index", type: :view do
  it "renders filters and pagination nav" do
    candidate = build_stubbed(:candidate_bump, base_branch: "master", gem_name: "rexml", target_version: "3.4.5")
    pr = build_stubbed(:pull_request, candidate_bump: candidate, status: "open", pr_number: 12_345)

    request_obj = Pagy::Request.new(request: { base_url: "http://test.host", path: "/admin/pull_requests", params: {} })
    pagy = Pagy::Offset.new(count: 1, page: 1, limit: 50, request: request_obj)

    assign(:pull_requests, [ pr ])
    assign(:pagy, pagy)

    render

    expect(rendered).to include("Pull requests")
    expect(rendered).to include("Status")
    expect(rendered).to include("series-nav")
  end
end
