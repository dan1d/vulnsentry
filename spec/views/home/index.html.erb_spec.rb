require "rails_helper"

RSpec.describe "home/index", type: :view do
  it "renders empty state" do
    assign(:merged_prs, [])
    render
    expect(rendered).to include("No merged PRs tracked yet")
  end
end
