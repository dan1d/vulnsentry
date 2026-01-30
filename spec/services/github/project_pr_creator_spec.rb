# frozen_string_literal: true

require "rails_helper"

RSpec.describe Github::ProjectPrCreator do
  let(:project) { create(:project, :ruby) }
  let(:branch_target) { create(:branch_target, project: project, name: "master") }
  let(:advisory) { create(:advisory, gem_name: "rexml", cve: "CVE-2026-0001") }
  let(:bundle) do
    create(:patch_bundle,
           branch_target: branch_target,
           gem_name: "rexml",
           target_version: "3.4.5",
           state: "approved")
  end
  let(:gh) { instance_double(Github::GhCli) }
  let(:creator) { described_class.new(project: project, gh: gh) }

  describe "#create_for_patch_bundle!" do
    it "raises error if bundle is not approved" do
      bundle.update!(state: "pending")

      expect { creator.create_for_patch_bundle!(bundle) }
        .to raise_error(Github::ProjectPrCreator::Error, /not approved/)
    end

    it "raises error if bundle already has a PR" do
      create(:pull_request, patch_bundle: bundle)

      expect { creator.create_for_patch_bundle!(bundle) }
        .to raise_error(Github::ProjectPrCreator::Error, /already has PR/)
    end

    it "raises error if bundle has no target version" do
      bundle.update!(target_version: nil, state: "approved")

      expect { creator.create_for_patch_bundle!(bundle) }
        .to raise_error(Github::ProjectPrCreator::Error, /no target version/)
    end

    it "raises error if project cannot create PRs" do
      project.update!(fork_repo: nil, fork_git_url: nil)

      expect { creator.create_for_patch_bundle!(bundle) }
        .to raise_error(Github::ProjectPrCreator::Error, /no fork configured/)
    end
  end

  describe "branch naming" do
    it "generates a valid branch name" do
      branch_name = creator.send(:branch_name_for_bundle, bundle)

      expect(branch_name).to eq("bump-rexml-3.4.5-master")
    end

    it "sanitizes special characters in branch names" do
      bundle.update!(gem_name: "gem-with-dashes", target_version: "1.0.0-rc.1")
      branch_name = creator.send(:branch_name_for_bundle, bundle)

      expect(branch_name).to match(/\Abump-gem-with-dashes-[\w.-]+-master\z/)
    end
  end

  describe "PR title generation" do
    it "generates appropriate PR title" do
      title = creator.send(:pr_title_for_bundle, bundle)

      expect(title).to eq("Bump rexml to 3.4.5 for master")
    end

    it "humanizes Ruby branch names" do
      bundle.branch_target.update!(name: "ruby_3_4")
      title = creator.send(:pr_title_for_bundle, bundle)

      expect(title).to include("Ruby 3.4")
    end
  end

  describe "PR body generation" do
    before do
      create(:bundled_advisory, patch_bundle: bundle, advisory: advisory, included_in_fix: true)
    end

    it "includes project name" do
      body = creator.send(:pr_body_for_bundle, bundle)

      expect(body).to include(project.name)
    end

    it "includes file path" do
      body = creator.send(:pr_body_for_bundle, bundle)

      expect(body).to include(project.file_path)
    end

    it "lists addressed advisories" do
      body = creator.send(:pr_body_for_bundle, bundle)

      expect(body).to include("CVE-2026-0001")
    end

    it "includes VulnSentry attribution" do
      body = creator.send(:pr_body_for_bundle, bundle)

      expect(body).to include("VulnSentry")
    end
  end
end
