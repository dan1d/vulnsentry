# frozen_string_literal: true

require "rails_helper"

RSpec.describe SystemEventKinds do
  describe "constants" do
    describe "ALL_KINDS" do
      it "contains all defined event kinds" do
        expect(SystemEventKinds::ALL_KINDS).to be_an(Array)
        expect(SystemEventKinds::ALL_KINDS).to be_frozen
        expect(SystemEventKinds::ALL_KINDS.length).to be >= 18
      end

      it "includes advisory kinds" do
        expect(SystemEventKinds::ALL_KINDS).to include(SystemEventKinds::ADVISORY_INGEST)
        expect(SystemEventKinds::ALL_KINDS).to include(SystemEventKinds::GHSA_INGEST)
        expect(SystemEventKinds::ALL_KINDS).to include(SystemEventKinds::OSV_INGEST)
        expect(SystemEventKinds::ALL_KINDS).to include(SystemEventKinds::RUBY_LANG_RESOLVER)
      end

      it "includes branch kinds" do
        expect(SystemEventKinds::ALL_KINDS).to include(SystemEventKinds::BRANCH_REFRESH)
        expect(SystemEventKinds::ALL_KINDS).to include(SystemEventKinds::FORK_BRANCH_CLEANUP)
      end

      it "includes evaluation kinds" do
        expect(SystemEventKinds::ALL_KINDS).to include(SystemEventKinds::BUNDLED_GEMS_FETCH)
        expect(SystemEventKinds::ALL_KINDS).to include(SystemEventKinds::PATCH_BUNDLE_BUILD)
        expect(SystemEventKinds::ALL_KINDS).to include(SystemEventKinds::PATCH_BUNDLE_REEVALUATION)
        expect(SystemEventKinds::ALL_KINDS).to include(SystemEventKinds::CANDIDATE_BUILD)
        expect(SystemEventKinds::ALL_KINDS).to include(SystemEventKinds::EVALUATION)
      end

      it "includes PR kinds" do
        expect(SystemEventKinds::ALL_KINDS).to include(SystemEventKinds::CREATE_PR)
        expect(SystemEventKinds::ALL_KINDS).to include(SystemEventKinds::CREATE_PATCH_BUNDLE_PR)
        expect(SystemEventKinds::ALL_KINDS).to include(SystemEventKinds::PR_CREATION)
        expect(SystemEventKinds::ALL_KINDS).to include(SystemEventKinds::SYNC_PULL_REQUESTS)
        expect(SystemEventKinds::ALL_KINDS).to include(SystemEventKinds::MAINTAINER_FEEDBACK)
      end

      it "includes system kinds" do
        expect(SystemEventKinds::ALL_KINDS).to include(SystemEventKinds::SEED)
      end
    end

    describe "category constants" do
      it "defines ADVISORY_KINDS" do
        expect(SystemEventKinds::ADVISORY_KINDS).to be_an(Array)
        expect(SystemEventKinds::ADVISORY_KINDS).to be_frozen
        expect(SystemEventKinds::ADVISORY_KINDS).to include("advisory_ingest")
        expect(SystemEventKinds::ADVISORY_KINDS).to include("ghsa_ingest")
        expect(SystemEventKinds::ADVISORY_KINDS).to include("osv_ingest")
        expect(SystemEventKinds::ADVISORY_KINDS).to include("ruby_lang_resolver")
      end

      it "defines BRANCH_KINDS" do
        expect(SystemEventKinds::BRANCH_KINDS).to be_an(Array)
        expect(SystemEventKinds::BRANCH_KINDS).to be_frozen
        expect(SystemEventKinds::BRANCH_KINDS).to include("branch_refresh")
        expect(SystemEventKinds::BRANCH_KINDS).to include("fork_branch_cleanup")
      end

      it "defines EVALUATION_KINDS" do
        expect(SystemEventKinds::EVALUATION_KINDS).to be_an(Array)
        expect(SystemEventKinds::EVALUATION_KINDS).to be_frozen
        expect(SystemEventKinds::EVALUATION_KINDS).to include("bundled_gems_fetch")
        expect(SystemEventKinds::EVALUATION_KINDS).to include("patch_bundle_build")
      end

      it "defines PR_KINDS" do
        expect(SystemEventKinds::PR_KINDS).to be_an(Array)
        expect(SystemEventKinds::PR_KINDS).to be_frozen
        expect(SystemEventKinds::PR_KINDS).to include("create_pr")
        expect(SystemEventKinds::PR_KINDS).to include("sync_pull_requests")
      end

      it "ensures all category arrays are subsets of ALL_KINDS" do
        all_categorized = SystemEventKinds::ADVISORY_KINDS +
                          SystemEventKinds::BRANCH_KINDS +
                          SystemEventKinds::EVALUATION_KINDS +
                          SystemEventKinds::PR_KINDS

        all_categorized.each do |kind|
          expect(SystemEventKinds::ALL_KINDS).to include(kind),
            "Expected ALL_KINDS to include '#{kind}' but it was missing"
        end
      end
    end
  end

  describe ".options_for_select" do
    subject(:options) { described_class.options_for_select }

    it "returns an array of label/value pairs" do
      expect(options).to be_an(Array)
      expect(options.first).to be_an(Array)
      expect(options.first.length).to eq(2)
    end

    it "has titleized labels" do
      labels = options.map(&:first)
      expect(labels).to include("Advisory Ingest")
      expect(labels).to include("Ghsa Ingest")
      expect(labels).to include("Branch Refresh")
      expect(labels).to include("Patch Bundle Build")
    end

    it "has snake_case values" do
      values = options.map(&:last)
      expect(values).to include("advisory_ingest")
      expect(values).to include("ghsa_ingest")
      expect(values).to include("branch_refresh")
      expect(values).to include("patch_bundle_build")
    end

    it "includes all kinds" do
      values = options.map(&:last)
      SystemEventKinds::ALL_KINDS.each do |kind|
        expect(values).to include(kind)
      end
    end
  end

  describe ".grouped_options_for_select" do
    subject(:grouped) { described_class.grouped_options_for_select }

    it "returns a hash of category to options" do
      expect(grouped).to be_a(Hash)
      expect(grouped.keys).to contain_exactly("Advisory", "Branch", "Evaluation", "Pull Request")
    end

    it "has Advisory group with correct options" do
      advisory_options = grouped["Advisory"]
      expect(advisory_options).to be_an(Array)
      expect(advisory_options.map(&:last)).to eq(SystemEventKinds::ADVISORY_KINDS)
    end

    it "has Branch group with correct options" do
      branch_options = grouped["Branch"]
      expect(branch_options).to be_an(Array)
      expect(branch_options.map(&:last)).to eq(SystemEventKinds::BRANCH_KINDS)
    end

    it "has Evaluation group with correct options" do
      eval_options = grouped["Evaluation"]
      expect(eval_options).to be_an(Array)
      expect(eval_options.map(&:last)).to eq(SystemEventKinds::EVALUATION_KINDS)
    end

    it "has Pull Request group with correct options" do
      pr_options = grouped["Pull Request"]
      expect(pr_options).to be_an(Array)
      expect(pr_options.map(&:last)).to eq(SystemEventKinds::PR_KINDS)
    end
  end

  describe ".valid_kind?" do
    it "returns true for valid kinds" do
      expect(described_class.valid_kind?("advisory_ingest")).to be true
      expect(described_class.valid_kind?("branch_refresh")).to be true
      expect(described_class.valid_kind?("patch_bundle_build")).to be true
      expect(described_class.valid_kind?("create_pr")).to be true
    end

    it "returns false for invalid kinds" do
      expect(described_class.valid_kind?("invalid_kind")).to be false
      expect(described_class.valid_kind?("")).to be false
      expect(described_class.valid_kind?(nil)).to be false
      expect(described_class.valid_kind?("ADVISORY_INGEST")).to be false # case sensitive
    end
  end

  describe "when included in a class" do
    # Create a test class to verify the concern works when included
    let(:test_class) do
      Class.new do
        include SystemEventKinds
      end
    end

    it "provides kind_options_for_select class method" do
      expect(test_class).to respond_to(:kind_options_for_select)
      expect(test_class.kind_options_for_select).to eq(described_class.options_for_select)
    end

    it "provides grouped_kind_options_for_select class method" do
      expect(test_class).to respond_to(:grouped_kind_options_for_select)
      expect(test_class.grouped_kind_options_for_select).to eq(described_class.grouped_options_for_select)
    end
  end
end
