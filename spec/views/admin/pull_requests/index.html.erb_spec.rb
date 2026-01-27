require "rails_helper"

RSpec.describe "admin/pull_requests/index", type: :view do
  it "renders filters and pagination nav" do
    candidate = build_stubbed(:candidate_bump, base_branch: "master", gem_name: "rexml", target_version: "3.4.5")
    pr = build_stubbed(:pull_request, candidate_bump: candidate, status: "open", pr_number: 12_345)

    assign(:pull_requests, Kaminari.paginate_array([ pr ]).page(1).per(50))

    render

    expect(rendered).to include("Pull requests")
    expect(rendered).to include("Status")
    expect(rendered).to include("Per page")
  end
end
