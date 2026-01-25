require "rails_helper"

RSpec.describe Ai::MaintenanceBranchesCrossCheck do
  it "raises on mismatch" do
    cross = described_class.new(client: instance_double(Ai::DeepseekClient, enabled?: true))

    deterministic = [ RubyLang::MaintenanceBranches::Branch.new("3.4", "normal") ]
    llm = [ RubyLang::MaintenanceBranches::Branch.new("3.4", "security") ]

    expect do
      cross.verify_match!(deterministic: deterministic, llm: llm)
    end.to raise_error(Ai::MaintenanceBranchesCrossCheck::MismatchError)
  end
end
