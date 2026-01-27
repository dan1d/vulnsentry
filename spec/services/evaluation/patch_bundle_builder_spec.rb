require "rails_helper"
require "ostruct"

RSpec.describe Evaluation::PatchBundleBuilder do
  subject(:builder) do
    described_class.new(
      version_resolver: version_resolver,
      ruby_lang_resolver: ruby_lang_resolver,
      ai_resolver: ai_resolver,
      cap_enforcer: cap_enforcer
    )
  end

  let(:version_resolver) { instance_double(RubyGems::VersionResolver) }
  let(:ruby_lang_resolver) { instance_double(RubyLang::SecurityAdvisoryResolver) }
  let(:ai_resolver) { instance_double(Ai::PatchVersionResolver) }
  let(:cap_enforcer) { instance_double(RateLimits::CapEnforcer) }

  let(:branch_target) { create(:branch_target, name: "ruby_3_0") }
  let(:advisory) { create(:advisory, gem_name: "rexml", cve: "CVE-2024-12345") }
  let(:entry) { OpenStruct.new(name: "rexml", version: "3.2.5") }
  let(:bundled_gems_content) { "rexml 3.2.5 https://github.com/ruby/rexml" }

  before do
    allow(ruby_lang_resolver).to receive(:resolve_fixed_version).and_return("3.2.7")
    allow(ai_resolver).to receive(:enabled?).and_return(false)
  end

  describe "#build!" do
    context "when fix is available and rate limit allows" do
      before do
        allow(version_resolver).to receive(:resolve_target_version).and_return(Gem::Version.new("3.2.7"))
        allow(cap_enforcer).to receive(:check!).and_return(
          OpenStruct.new(allowed: true, reason: nil, next_eligible_at: nil)
        )
        allow(RubyCore::BundledGemsBumper).to receive(:bump!).and_return({
          old_line: "rexml 3.2.5 https://github.com/ruby/rexml",
          new_line: "rexml 3.2.7 https://github.com/ruby/rexml",
          new_content: "rexml 3.2.7 https://github.com/ruby/rexml"
        })
      end

      it "creates a PatchBundle in ready_for_review state" do
        result = builder.build!(
          branch_target: branch_target,
          bundled_gems_content: bundled_gems_content,
          entry: entry,
          advisory: advisory
        )

        expect(result).to be_a(PatchBundle)
        expect(result.state).to eq("ready_for_review")
        expect(result.target_version).to eq("3.2.7")
        expect(result.gem_name).to eq("rexml")
      end

      it "links the advisory to the bundle" do
        result = builder.build!(
          branch_target: branch_target,
          bundled_gems_content: bundled_gems_content,
          entry: entry,
          advisory: advisory
        )

        expect(result.advisories).to include(advisory)
        expect(result.bundled_advisories.first.suggested_fix_version).to eq("3.2.7")
      end
    end

    context "when fix is available but rate limited" do
      before do
        allow(version_resolver).to receive(:resolve_target_version).and_return(Gem::Version.new("3.2.7"))
        allow(cap_enforcer).to receive(:check!).and_return(
          OpenStruct.new(allowed: false, reason: "global_hourly_cap", next_eligible_at: 1.hour.from_now)
        )
        allow(RubyCore::BundledGemsBumper).to receive(:bump!).and_return({
          old_line: "rexml 3.2.5 https://github.com/ruby/rexml",
          new_line: "rexml 3.2.7 https://github.com/ruby/rexml",
          new_content: "rexml 3.2.7 https://github.com/ruby/rexml"
        })
      end

      it "creates a PatchBundle in blocked_rate_limited state" do
        result = builder.build!(
          branch_target: branch_target,
          bundled_gems_content: bundled_gems_content,
          entry: entry,
          advisory: advisory
        )

        expect(result.state).to eq("blocked_rate_limited")
        expect(result.blocked_reason).to eq("global_hourly_cap")
      end
    end

    context "when no fix version is available" do
      before do
        allow(ruby_lang_resolver).to receive(:resolve_fixed_version).and_return(nil)
      end

      it "creates a PatchBundle in awaiting_fix state" do
        result = builder.build!(
          branch_target: branch_target,
          bundled_gems_content: bundled_gems_content,
          entry: entry,
          advisory: advisory
        )

        expect(result.state).to eq("awaiting_fix")
        expect(result.target_version).to be_nil
        expect(result.blocked_reason).to eq("no_fixed_version_available")
      end
    end

    context "when resolution fails with an error" do
      before do
        allow(ruby_lang_resolver).to receive(:resolve_fixed_version).and_return("3.2.7")
        allow(RubyCore::BundledGemsBumper).to receive(:bump!).and_raise(
          RubyCore::DiffValidator::ValidationError.new("No matching version")
        )
      end

      it "creates a PatchBundle in awaiting_fix state with error details" do
        result = builder.build!(
          branch_target: branch_target,
          bundled_gems_content: bundled_gems_content,
          entry: entry,
          advisory: advisory
        )

        expect(result.state).to eq("awaiting_fix")
        expect(result.blocked_reason).to include("bump_generation_failed: No matching version")
      end
    end

    context "when adding multiple advisories to the same bundle" do
      let(:advisory2) { create(:advisory, gem_name: "rexml", cve: "CVE-2024-67890") }

      before do
        allow(version_resolver).to receive(:resolve_target_version).and_return(Gem::Version.new("3.2.7"))
        allow(cap_enforcer).to receive(:check!).and_return(
          OpenStruct.new(allowed: true, reason: nil, next_eligible_at: nil)
        )
        allow(RubyCore::BundledGemsBumper).to receive(:bump!).and_return({
          old_line: "rexml 3.2.5 https://github.com/ruby/rexml",
          new_line: "rexml 3.2.7 https://github.com/ruby/rexml",
          new_content: "rexml 3.2.7 https://github.com/ruby/rexml"
        })
      end

      it "links multiple advisories to the same bundle" do
        bundle1 = builder.build!(
          branch_target: branch_target,
          bundled_gems_content: bundled_gems_content,
          entry: entry,
          advisory: advisory
        )

        bundle2 = builder.build!(
          branch_target: branch_target,
          bundled_gems_content: bundled_gems_content,
          entry: entry,
          advisory: advisory2
        )

        expect(bundle1.id).to eq(bundle2.id)
        expect(bundle1.advisories.count).to eq(2)
        expect(bundle1.advisories).to include(advisory, advisory2)
      end
    end
  end

  describe "#reevaluate!" do
    let(:bundle) do
      create(:patch_bundle, :awaiting_fix,
        branch_target: branch_target,
        gem_name: "rexml",
        current_version: "3.2.5"
      )
    end

    before do
      create(:bundled_advisory, patch_bundle: bundle, advisory: advisory, suggested_fix_version: nil)

      allow(ruby_lang_resolver).to receive(:resolve_fixed_version).and_return("3.2.7")
      allow(version_resolver).to receive(:resolve_target_version).and_return(Gem::Version.new("3.2.7"))
      allow(cap_enforcer).to receive(:check!).and_return(
        OpenStruct.new(allowed: true, reason: nil, next_eligible_at: nil)
      )
      allow(RubyCore::BundledGemsBumper).to receive(:bump!).and_return({
        old_line: "rexml 3.2.5 https://github.com/ruby/rexml",
        new_line: "rexml 3.2.7 https://github.com/ruby/rexml",
        new_content: "rexml 3.2.7 https://github.com/ruby/rexml"
      })
    end

    it "updates the bundle when fix becomes available" do
      builder.reevaluate!(bundle, bundled_gems_content: bundled_gems_content)

      bundle.reload
      expect(bundle.state).to eq("ready_for_review")
      expect(bundle.target_version).to eq("3.2.7")
      expect(bundle.last_evaluated_at).to be_present
    end
  end
end
