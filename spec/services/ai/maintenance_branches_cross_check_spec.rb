require "rails_helper"

RSpec.describe Ai::MaintenanceBranchesCrossCheck do
  it "raises on mismatch with detailed diff" do
    cross = described_class.new(client: instance_double(Ai::DeepseekClient, enabled?: true))

    deterministic = [ RubyLang::MaintenanceBranches::Branch.new("3.4", "normal") ]
    llm = [ RubyLang::MaintenanceBranches::Branch.new("3.4", "security") ]

    expect do
      cross.verify_match!(deterministic: deterministic, llm: llm)
    end.to raise_error(Ai::MaintenanceBranchesCrossCheck::MismatchError, /deterministic_only.*3\.4.*normal/)
  end

  it "returns true when deterministic and LLM results match" do
    cross = described_class.new(client: instance_double(Ai::DeepseekClient, enabled?: true))

    branches = [
      RubyLang::MaintenanceBranches::Branch.new("3.4", "normal"),
      RubyLang::MaintenanceBranches::Branch.new("3.3", "security")
    ]

    expect(cross.verify_match!(deterministic: branches, llm: branches)).to be true
  end
end
