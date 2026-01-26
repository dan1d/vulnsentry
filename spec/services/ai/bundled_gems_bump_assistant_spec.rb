require "rails_helper"

RSpec.describe Ai::BundledGemsBumpAssistant do
  it "refuses when not enabled" do
    assistant = described_class.new(client: instance_double(Ai::DeepseekClient, enabled?: false))
    expect(assistant.enabled?).to be(false)
  end

  it "applies one-line bump when deepseek returns valid JSON" do
    client = instance_double(Ai::DeepseekClient, enabled?: true)
    allow(client).to receive(:extract_json!).and_return(
      {
        "line_number" => 2,
        "old_line" => "rexml 3.3.8 https://github.com/ruby/rexml\n",
        "new_line" => "rexml 3.3.9 https://github.com/ruby/rexml"
      }
    )

    stub_const("ENV", ENV.to_hash.merge("ENABLE_DEEPSEEK_BUNDLED_GEMS_ASSIST" => "true"))

    assistant = described_class.new(client: client)

    old = <<~TXT
      # comment
      rexml 3.3.8 https://github.com/ruby/rexml
      rake 13.0.0 https://github.com/ruby/rake
    TXT

    result = assistant.suggest_bump!(old_content: old, gem_name: "rexml", target_version: "3.3.9")
    expect(result[:new_content]).to include("rexml 3.3.9 https://github.com/ruby/rexml")
    expect(result[:changed_line_number]).to eq(2)
  end
end
