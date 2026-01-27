require "rails_helper"

RSpec.describe "home/index", type: :view do
  it "renders empty state" do
    assign(:pull_requests, [])
    render
    expect(rendered).to include("No PRs tracked yet")
  end
end
