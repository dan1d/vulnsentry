# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectFiles::GemfileLockBumper do
  let(:sample_lockfile) do
    <<~LOCKFILE
GEM
  remote: https://rubygems.org/
  specs:
    actioncable (7.1.3)
      actionpack (= 7.1.3)
      activesupport (= 7.1.3)
    actionpack (7.1.3)
      rack (~> 2.2)
    nokogiri (1.16.0)
      mini_portile2 (~> 2.8.2)
    rack (2.2.8)
    rexml (3.4.4)

PLATFORMS
  ruby

BUNDLED WITH
  2.5.3
    LOCKFILE
  end

  describe ".bump!" do
    context "with a simple gem (no dependencies referencing it)" do
      it "updates the gem version in the specs section" do
        result = described_class.bump!(
          old_content: sample_lockfile,
          gem_name: "rexml",
          target_version: "3.4.5"
        )

        expect(result[:new_content]).to include("rexml (3.4.5)")
        expect(result[:new_content]).not_to include("rexml (3.4.4)")
        expect(result[:old_line]).to include("rexml (3.4.4)")
        expect(result[:new_line]).to include("rexml (3.4.5)")
        expect(result[:diff][:changed_line_count]).to eq(1)
      end
    end

    context "with a gem that has exact version dependencies" do
      it "updates both the spec and dependency constraints" do
        result = described_class.bump!(
          old_content: sample_lockfile,
          gem_name: "actionpack",
          target_version: "7.1.4"
        )

        expect(result[:new_content]).to include("actionpack (7.1.4)")
        expect(result[:new_content]).to include("actionpack (= 7.1.4)")
        expect(result[:new_content]).not_to include("actionpack (7.1.3)")
        # Should have multiple line changes (spec + dependency)
        expect(result[:diff][:changed_line_count]).to be >= 1
      end
    end

    context "with a gem that doesn't exist" do
      it "raises ParseError" do
        expect {
          described_class.bump!(
            old_content: sample_lockfile,
            gem_name: "nonexistent_gem",
            target_version: "1.0.0"
          )
        }.to raise_error(ProjectFiles::GemfileLockFile::ParseError, /gem not found/)
      end
    end

    context "when version is the same (no change)" do
      it "raises BumpError" do
        expect {
          described_class.bump!(
            old_content: sample_lockfile,
            gem_name: "rexml",
            target_version: "3.4.4"  # Same as current
          )
        }.to raise_error(ProjectFiles::GemfileLockBumper::BumpError, /No changes detected/)
      end
    end

    context "with nokogiri (has platform variants in real lockfiles)" do
      it "updates the gem version" do
        result = described_class.bump!(
          old_content: sample_lockfile,
          gem_name: "nokogiri",
          target_version: "1.16.1"
        )

        expect(result[:new_content]).to include("nokogiri (1.16.1)")
        expect(result[:old_line]).to include("nokogiri (1.16.0)")
        expect(result[:new_line]).to include("nokogiri (1.16.1)")
      end
    end

    context "maintains lockfile structure" do
      it "preserves line count" do
        result = described_class.bump!(
          old_content: sample_lockfile,
          gem_name: "rack",
          target_version: "2.2.9"
        )

        expect(result[:new_content].lines.count).to eq(sample_lockfile.lines.count)
      end

      it "preserves other sections" do
        result = described_class.bump!(
          old_content: sample_lockfile,
          gem_name: "rack",
          target_version: "2.2.9"
        )

        expect(result[:new_content]).to include("PLATFORMS")
        expect(result[:new_content]).to include("ruby")
        expect(result[:new_content]).to include("BUNDLED WITH")
        expect(result[:new_content]).to include("2.5.3")
      end
    end
  end
end
