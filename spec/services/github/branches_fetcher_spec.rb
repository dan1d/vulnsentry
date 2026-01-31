# frozen_string_literal: true

require "rails_helper"

RSpec.describe Github::BranchesFetcher do
  let(:gh_cli) { instance_double(Github::GhCli) }
  subject(:fetcher) { described_class.new(gh: gh_cli) }

  describe "#fetch_all" do
    context "when branches exist" do
      before do
        allow(gh_cli).to receive(:json!).with(
          "api",
          "repos/rails/rails/branches",
          "--paginate",
          "--jq", ".[].name"
        ).and_return("main\n7-2-stable\n7-1-stable\n7-0-stable\n")
      end

      it "returns an array of BranchInfo objects" do
        branches = fetcher.fetch_all(repo: "rails/rails")

        expect(branches).to all(be_a(Github::BranchesFetcher::BranchInfo))
        expect(branches.map(&:name)).to eq(%w[main 7-2-stable 7-1-stable 7-0-stable])
      end

      it "sets protected to false and commit_sha to nil" do
        branches = fetcher.fetch_all(repo: "rails/rails")

        branches.each do |branch|
          expect(branch.protected).to be false
          expect(branch.commit_sha).to be_nil
        end
      end
    end

    context "when repository has no branches" do
      before do
        allow(gh_cli).to receive(:json!).and_return("")
      end

      it "returns an empty array" do
        branches = fetcher.fetch_all(repo: "empty/repo")
        expect(branches).to eq([])
      end
    end

    context "when GitHub API call fails" do
      before do
        allow(gh_cli).to receive(:json!).and_raise(
          Github::GhCli::CommandError.new(
            "gh command failed",
            cmd: ["gh", "api"],
            stdout: "",
            stderr: "Not Found",
            status: nil
          )
        )
      end

      it "raises a FetchError" do
        expect {
          fetcher.fetch_all(repo: "nonexistent/repo")
        }.to raise_error(Github::BranchesFetcher::FetchError, /Failed to fetch branches/)
      end
    end
  end

  describe "#fetch_matching" do
    before do
      allow(gh_cli).to receive(:json!).and_return("main\n7-2-stable\n7-1-stable\nfeature-branch\nfix/bug\n")
    end

    it "returns branches matching the given pattern" do
      pattern = /^\d+-\d+-stable$/
      branches = fetcher.fetch_matching(repo: "rails/rails", pattern: pattern)

      expect(branches.map(&:name)).to eq(%w[7-2-stable 7-1-stable])
    end

    it "returns empty array when no branches match" do
      pattern = /^release-/
      branches = fetcher.fetch_matching(repo: "rails/rails", pattern: pattern)

      expect(branches).to eq([])
    end
  end

  describe "#fetch_rails_stable_branches" do
    context "with typical Rails branch setup" do
      before do
        allow(gh_cli).to receive(:json!).and_return(
          "main\n7-2-stable\n7-1-stable\n7-0-stable\n6-1-stable\nfeature-branch\n"
        )
      end

      it "returns main/master branch first" do
        branches = fetcher.fetch_rails_stable_branches(repo: "rails/rails")

        expect(branches.first.name).to eq("main")
      end

      it "returns stable branches sorted by version descending" do
        branches = fetcher.fetch_rails_stable_branches(repo: "rails/rails")

        stable_names = branches.map(&:name).reject { |n| n == "main" }
        expect(stable_names).to eq(%w[7-2-stable 7-1-stable 7-0-stable 6-1-stable])
      end

      it "excludes non-stable branches" do
        branches = fetcher.fetch_rails_stable_branches(repo: "rails/rails")

        expect(branches.map(&:name)).not_to include("feature-branch")
      end
    end

    context "with master instead of main" do
      before do
        allow(gh_cli).to receive(:json!).and_return(
          "master\n5-2-stable\n5-1-stable\n"
        )
      end

      it "returns master branch first" do
        branches = fetcher.fetch_rails_stable_branches(repo: "rails/rails")

        expect(branches.first.name).to eq("master")
      end
    end

    context "with no main/master branch" do
      before do
        allow(gh_cli).to receive(:json!).and_return(
          "7-2-stable\n7-1-stable\n"
        )
      end

      it "returns only stable branches" do
        branches = fetcher.fetch_rails_stable_branches(repo: "rails/rails")

        expect(branches.map(&:name)).to eq(%w[7-2-stable 7-1-stable])
      end
    end

    context "with no stable branches" do
      before do
        allow(gh_cli).to receive(:json!).and_return(
          "main\nfeature-x\nbugfix-y\n"
        )
      end

      it "returns only main branch" do
        branches = fetcher.fetch_rails_stable_branches(repo: "rails/rails")

        expect(branches.map(&:name)).to eq(["main"])
      end
    end
  end

  describe "version sorting" do
    before do
      # Out of order versions to verify sorting
      allow(gh_cli).to receive(:json!).and_return(
        "6-1-stable\n7-0-stable\n7-2-stable\n5-2-stable\n7-1-stable\n"
      )
    end

    it "sorts versions correctly with major and minor components" do
      branches = fetcher.fetch_rails_stable_branches(repo: "rails/rails")

      expect(branches.map(&:name)).to eq(%w[7-2-stable 7-1-stable 7-0-stable 6-1-stable 5-2-stable])
    end
  end
end
