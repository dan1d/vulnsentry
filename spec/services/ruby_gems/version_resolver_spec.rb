require "rails_helper"

RSpec.describe RubyGems::VersionResolver do
  let(:resolver) { described_class.new }

  def stub_rubygems_versions(gem_name, versions)
    stub_request(:get, "https://rubygems.org/api/v1/versions/#{gem_name}.json")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: versions.map { |v| { "number" => v } }.to_json
      )
  end

  it "uses fixed_version when provided and allowed" do
    stub_rubygems_versions("rexml", %w[3.4.4 3.4.5 3.4.6])
    version = resolver.resolve_target_version(
      gem_name: "rexml",
      affected_requirement: "< 3.4.5",
      current_version: "3.4.4",
      fixed_version: "3.4.5",
      allow_major_minor: false
    )

    expect(version.to_s).to eq("3.4.5")
  end

  it "finds minimal safe patch bump when fixed_version is absent" do
    stub_rubygems_versions("rexml", %w[3.4.4 3.4.5 3.4.6])
    version = resolver.resolve_target_version(
      gem_name: "rexml",
      affected_requirement: "< 3.4.5",
      current_version: "3.4.4",
      fixed_version: nil,
      allow_major_minor: false
    )

    expect(version.to_s).to eq("3.4.5")
  end

  it "rejects major/minor bump when not allowed" do
    stub_rubygems_versions("rake", %w[12.3.3 12.3.4 13.3.1 13.3.2])
    expect do
      resolver.resolve_target_version(
        gem_name: "rake",
        affected_requirement: "< 13.3.1",
        current_version: "12.3.3",
        fixed_version: nil,
        allow_major_minor: false
      )
    end.to raise_error(RubyGems::VersionResolver::ResolutionError, /major\/minor bump not allowed/i)
  end
end
