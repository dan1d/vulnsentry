# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectFiles::GemfileLockFile do
  let(:sample_lockfile) do
    <<~LOCKFILE
GEM
  remote: https://rubygems.org/
  specs:
    actioncable (7.1.3)
      actionpack (= 7.1.3)
      activesupport (= 7.1.3)
      nio4r (~> 2.0)
      websocket-driver (>= 0.6.1)
    actionpack (7.1.3)
      actionview (= 7.1.3)
      activesupport (= 7.1.3)
      rack (~> 2.2, >= 2.2.4)
    nokogiri (1.16.0)
      mini_portile2 (~> 2.8.2)
      racc (~> 1.4)
    rack (2.2.8)
    rexml (3.4.4)

PLATFORMS
  ruby
  x86_64-linux

DEPENDENCIES
  actioncable
  nokogiri
  rexml

BUNDLED WITH
  2.5.3
    LOCKFILE
  end

  describe "#entries" do
    it "parses all gems from the GEM specs section" do
      file = described_class.new(sample_lockfile)
      entries = file.entries

      expect(entries.map(&:name)).to contain_exactly(
        "actioncable",
        "actionpack",
        "nokogiri",
        "rack",
        "rexml"
      )
    end

    it "extracts correct versions" do
      file = described_class.new(sample_lockfile)

      expect(file.version_of("actioncable")).to eq("7.1.3")
      expect(file.version_of("nokogiri")).to eq("1.16.0")
      expect(file.version_of("rack")).to eq("2.2.8")
      expect(file.version_of("rexml")).to eq("3.4.4")
    end

    it "includes line numbers" do
      file = described_class.new(sample_lockfile)
      entry = file.find_entry("actioncable")

      expect(entry.line_number).to be > 0
    end
  end

  describe "#find_entry" do
    it "finds a gem by name" do
      file = described_class.new(sample_lockfile)
      entry = file.find_entry("nokogiri")

      expect(entry).not_to be_nil
      expect(entry.name).to eq("nokogiri")
      expect(entry.version).to eq("1.16.0")
    end

    it "returns nil for non-existent gems" do
      file = described_class.new(sample_lockfile)
      expect(file.find_entry("nonexistent")).to be_nil
    end
  end

  describe "#has_gem?" do
    it "returns true for existing gems" do
      file = described_class.new(sample_lockfile)
      expect(file.has_gem?("rack")).to be true
    end

    it "returns false for non-existent gems" do
      file = described_class.new(sample_lockfile)
      expect(file.has_gem?("nonexistent")).to be false
    end
  end

  describe "#bump_version!" do
    it "updates the gem version in the lockfile" do
      file = described_class.new(sample_lockfile)
      new_content, old_line, new_line = file.bump_version!("rexml", "3.4.5")

      expect(old_line).to include("rexml (3.4.4)")
      expect(new_line).to include("rexml (3.4.5)")
      expect(new_content).to include("rexml (3.4.5)")
      expect(new_content).not_to include("rexml (3.4.4)")
    end

    it "updates version references in dependency constraints" do
      file = described_class.new(sample_lockfile)
      new_content, _old_line, _new_line = file.bump_version!("actionpack", "7.2.0")

      # The spec line should be updated
      expect(new_content).to include("actionpack (7.2.0)")

      # Exact version constraints in dependencies should be updated
      expect(new_content).to include("actionpack (= 7.2.0)")
      expect(new_content).not_to include("actionpack (7.1.3)")
    end

    it "raises ParseError for non-existent gems" do
      file = described_class.new(sample_lockfile)

      expect { file.bump_version!("nonexistent", "1.0.0") }
        .to raise_error(ProjectFiles::Base::ParseError, /gem not found/)
    end
  end

  describe "Entry#with_version" do
    it "creates a new entry with updated version" do
      file = described_class.new(sample_lockfile)
      entry = file.find_entry("rack")

      new_entry = entry.with_version("3.0.0")

      expect(new_entry.name).to eq("rack")
      expect(new_entry.version).to eq("3.0.0")
      expect(new_entry.raw_line).to include("rack (3.0.0)")
    end
  end
end
