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

    assign(:candidate_bumps, Kaminari.paginate_array([ candidate ]).page(1).per(50))

    render

    expect(rendered).to include("Candidate bumps")
    expect(rendered).to include("Filter")
    expect(rendered).to include("Per page")
  end
end
