require "rails_helper"

RSpec.describe RubyCore::BundledGemsBumper do
  let(:content) do
    <<~TXT
      # comment
      rexml 3.4.4 https://github.com/ruby/rexml
      net-imap 0.6.2 https://github.com/ruby/net-imap deadbeef
    TXT
  end

  it "bumps version with a single-line change" do
    result = described_class.bump!(old_content: content, gem_name: "rexml", target_version: "3.4.5")

    expect(result[:new_content]).to include("rexml 3.4.5 https://github.com/ruby/rexml\n")
    expect(result[:new_content]).to include("net-imap 0.6.2 https://github.com/ruby/net-imap deadbeef\n")
    expect(result[:diff][:changed_line_number]).to eq(2)
  end

  it "raises if the gem is not present" do
    expect do
      described_class.bump!(old_content: content, gem_name: "nokogiri", target_version: "1.0.0")
    end.to raise_error(RubyCore::BundledGemsFile::ParseError, /gem not found/i)
  end
end

