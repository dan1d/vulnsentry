# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectFiles::BundledGemsFile do
  let(:sample_content) do
    <<~CONTENT
      # This is a comment
      rexml 3.4.4 https://github.com/ruby/rexml
      json 2.9.1 https://github.com/ruby/json 7eba852
      rake 13.2.1 https://github.com/ruby/rake
      uri 0.13.0 https://github.com/ruby/uri
    CONTENT
  end

  describe "#entries" do
    it "parses all gem entries" do
      file = described_class.new(sample_content)
      entries = file.entries

      expect(entries.map(&:name)).to contain_exactly("rexml", "json", "rake", "uri")
    end

    it "extracts correct versions" do
      file = described_class.new(sample_content)

      expect(file.version_of("rexml")).to eq("3.4.4")
      expect(file.version_of("json")).to eq("2.9.1")
      expect(file.version_of("rake")).to eq("13.2.1")
    end

    it "extracts repository URLs" do
      file = described_class.new(sample_content)
      entry = file.find_entry("rexml")

      expect(entry.repo_url).to eq("https://github.com/ruby/rexml")
    end

    it "extracts revision when present" do
      file = described_class.new(sample_content)
      json_entry = file.find_entry("json")
      rexml_entry = file.find_entry("rexml")

      expect(json_entry.revision).to eq("7eba852")
      expect(rexml_entry.revision).to be_nil
    end

    it "ignores comments" do
      file = described_class.new(sample_content)
      expect(file.entries.map(&:name)).not_to include("#")
    end

    it "ignores blank lines" do
      content = "rexml 3.4.4 https://github.com/ruby/rexml\n\njson 2.9.1 https://github.com/ruby/json\n"
      file = described_class.new(content)

      expect(file.entries.count).to eq(2)
    end

    it "includes line numbers" do
      file = described_class.new(sample_content)
      entry = file.find_entry("rexml")

      # Line 1 is comment, line 2 is rexml
      expect(entry.line_number).to eq(2)
    end
  end

  describe "#find_entry" do
    it "finds a gem by name" do
      file = described_class.new(sample_content)
      entry = file.find_entry("rake")

      expect(entry).not_to be_nil
      expect(entry.name).to eq("rake")
      expect(entry.version).to eq("13.2.1")
    end

    it "returns nil for non-existent gems" do
      file = described_class.new(sample_content)
      expect(file.find_entry("nonexistent")).to be_nil
    end
  end

  describe "#has_gem?" do
    it "returns true for existing gems" do
      file = described_class.new(sample_content)
      expect(file.has_gem?("uri")).to be true
    end

    it "returns false for non-existent gems" do
      file = described_class.new(sample_content)
      expect(file.has_gem?("nonexistent")).to be false
    end
  end

  describe "#bump_version!" do
    it "updates the gem version" do
      file = described_class.new(sample_content)
      new_content, old_line, new_line = file.bump_version!("rexml", "3.4.5")

      expect(old_line).to include("rexml 3.4.4")
      expect(new_line).to include("rexml 3.4.5")
      expect(new_content).to include("rexml 3.4.5 https://github.com/ruby/rexml")
      expect(new_content).not_to include("rexml 3.4.4")
    end

    it "preserves other entries" do
      file = described_class.new(sample_content)
      new_content, _old_line, _new_line = file.bump_version!("rexml", "3.4.5")

      expect(new_content).to include("json 2.9.1")
      expect(new_content).to include("rake 13.2.1")
    end

    it "raises ParseError for non-existent gems" do
      file = described_class.new(sample_content)

      expect { file.bump_version!("nonexistent", "1.0.0") }
        .to raise_error(ProjectFiles::Base::ParseError, /gem not found/)
    end
  end

  describe "Entry#with_version" do
    it "creates a new entry with updated version" do
      file = described_class.new(sample_content)
      entry = file.find_entry("json")

      new_entry = entry.with_version("2.10.0")

      expect(new_entry.name).to eq("json")
      expect(new_entry.version).to eq("2.10.0")
      expect(new_entry.raw_line).to include("json 2.10.0")
      expect(new_entry.revision).to eq("7eba852")
    end
  end

  describe "backwards compatibility" do
    it "is accessible via RubyCore::BundledGemsFile alias" do
      expect(RubyCore::BundledGemsFile).to eq(ProjectFiles::BundledGemsFile)
    end
  end

  describe "parse error handling" do
    it "raises ParseError for malformed lines" do
      content = "invalid line with only two parts\n"

      expect { described_class.new(content).entries }
        .to raise_error(ProjectFiles::Base::ParseError, /invalid bundled_gems line/)
    end
  end
end
