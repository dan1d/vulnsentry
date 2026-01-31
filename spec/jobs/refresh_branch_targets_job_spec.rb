require "rails_helper"

RSpec.describe RefreshBranchTargetsJob, type: :job do
  let!(:ruby_project) { create(:project, :ruby) }

  before do
    allow_any_instance_of(Ai::MaintenanceBranchesCrossCheck).to receive(:enabled?).and_return(false)
  end

  describe "ruby_lang branch discovery" do
    it "creates/updates branch targets for supported branches and ensures master" do
      fake_fetcher = instance_double(RubyLang::MaintenanceBranches)
      allow(RubyLang::MaintenanceBranches).to receive(:new).and_return(fake_fetcher)
      allow(fake_fetcher).to receive(:fetch_html).and_return("<html/>")
      allow(fake_fetcher).to receive(:parse_all_html).and_return([
        RubyLang::MaintenanceBranches::Branch.new("3.4", "normal"),
        RubyLang::MaintenanceBranches::Branch.new("3.2", "security"),
        RubyLang::MaintenanceBranches::Branch.new("3.1", "eol")
      ])

      described_class.perform_now

      expect(ruby_project.branch_targets.find_by!(name: "ruby_3_4").maintenance_status).to eq("normal")
      expect(ruby_project.branch_targets.find_by!(name: "ruby_3_2").maintenance_status).to eq("security")
      expect(ruby_project.branch_targets.find_by!(name: "ruby_3_1")).to have_attributes(maintenance_status: "eol", enabled: false)
      expect(ruby_project.branch_targets.find_by!(name: "master")).to be_present
    end

    it "marks branches no longer on ruby-lang.org as EOL" do
      # Simulate an old branch that was once supported but is now gone from the page
      old_branch = create(:branch_target,
        project: ruby_project,
        name: "ruby_3_0",
        maintenance_status: "security",
        enabled: true,
        source_url: "https://www.ruby-lang.org/en/downloads/branches/"
      )

      fake_fetcher = instance_double(RubyLang::MaintenanceBranches)
      allow(RubyLang::MaintenanceBranches).to receive(:new).and_return(fake_fetcher)
      allow(fake_fetcher).to receive(:fetch_html).and_return("<html/>")
      # 3.0 is no longer on the page at all
      allow(fake_fetcher).to receive(:parse_all_html).and_return([
        RubyLang::MaintenanceBranches::Branch.new("3.4", "normal"),
        RubyLang::MaintenanceBranches::Branch.new("3.3", "normal")
      ])

      described_class.perform_now

      old_branch.reload
      expect(old_branch.maintenance_status).to eq("eol")
      expect(old_branch.enabled).to be false
    end

    it "does not mark master as EOL even if not on page" do
      create(:branch_target, project: ruby_project, name: "master", maintenance_status: "normal", enabled: true)

      fake_fetcher = instance_double(RubyLang::MaintenanceBranches)
      allow(RubyLang::MaintenanceBranches).to receive(:new).and_return(fake_fetcher)
      allow(fake_fetcher).to receive(:fetch_html).and_return("<html/>")
      allow(fake_fetcher).to receive(:parse_all_html).and_return([
        RubyLang::MaintenanceBranches::Branch.new("3.4", "normal")
      ])

      described_class.perform_now

      master = ruby_project.branch_targets.find_by!(name: "master")
      expect(master.maintenance_status).to eq("normal")
      expect(master.enabled).to be true
    end
  end

  describe "github_releases branch discovery" do
    let!(:rails_project) { create(:project, :rails) }

    before do
      # Disable the ruby_lang fetcher since we also have a ruby project
      allow(RubyLang::MaintenanceBranches).to receive(:new).and_return(
        instance_double(RubyLang::MaintenanceBranches,
          fetch_html: "<html/>",
          parse_all_html: []
        )
      )
    end

    it "fetches branches from GitHub and creates branch targets" do
      gh_fetcher = instance_double(Github::BranchesFetcher)
      allow(Github::BranchesFetcher).to receive(:new).and_return(gh_fetcher)
      allow(gh_fetcher).to receive(:fetch_rails_stable_branches).with(repo: "rails/rails").and_return([
        Github::BranchesFetcher::BranchInfo.new(name: "main", protected: false, commit_sha: nil),
        Github::BranchesFetcher::BranchInfo.new(name: "7-2-stable", protected: false, commit_sha: nil),
        Github::BranchesFetcher::BranchInfo.new(name: "7-1-stable", protected: false, commit_sha: nil),
        Github::BranchesFetcher::BranchInfo.new(name: "7-0-stable", protected: false, commit_sha: nil)
      ])

      described_class.perform_now

      expect(rails_project.branch_targets.count).to eq(4)
      expect(rails_project.branch_targets.pluck(:name)).to contain_exactly("main", "7-2-stable", "7-1-stable", "7-0-stable")
    end

    it "sets main/master branch as normal status" do
      gh_fetcher = instance_double(Github::BranchesFetcher)
      allow(Github::BranchesFetcher).to receive(:new).and_return(gh_fetcher)
      allow(gh_fetcher).to receive(:fetch_rails_stable_branches).with(repo: "rails/rails").and_return([
        Github::BranchesFetcher::BranchInfo.new(name: "main", protected: false, commit_sha: nil),
        Github::BranchesFetcher::BranchInfo.new(name: "7-2-stable", protected: false, commit_sha: nil)
      ])

      described_class.perform_now

      main_branch = rails_project.branch_targets.find_by!(name: "main")
      expect(main_branch.maintenance_status).to eq("normal")
    end

    it "sets newest stable branches as normal, older as security" do
      gh_fetcher = instance_double(Github::BranchesFetcher)
      allow(Github::BranchesFetcher).to receive(:new).and_return(gh_fetcher)
      allow(gh_fetcher).to receive(:fetch_rails_stable_branches).with(repo: "rails/rails").and_return([
        Github::BranchesFetcher::BranchInfo.new(name: "main", protected: false, commit_sha: nil),
        Github::BranchesFetcher::BranchInfo.new(name: "7-2-stable", protected: false, commit_sha: nil),
        Github::BranchesFetcher::BranchInfo.new(name: "7-1-stable", protected: false, commit_sha: nil),
        Github::BranchesFetcher::BranchInfo.new(name: "7-0-stable", protected: false, commit_sha: nil),
        Github::BranchesFetcher::BranchInfo.new(name: "6-1-stable", protected: false, commit_sha: nil)
      ])

      described_class.perform_now

      # Newest 2 stable branches should be "normal"
      expect(rails_project.branch_targets.find_by!(name: "7-2-stable").maintenance_status).to eq("normal")
      expect(rails_project.branch_targets.find_by!(name: "7-1-stable").maintenance_status).to eq("normal")

      # Older branches should be "security"
      expect(rails_project.branch_targets.find_by!(name: "7-0-stable").maintenance_status).to eq("security")
      expect(rails_project.branch_targets.find_by!(name: "6-1-stable").maintenance_status).to eq("security")
    end

    it "marks branches no longer on GitHub as EOL" do
      # Pre-create an old branch
      old_branch = create(:branch_target,
        project: rails_project,
        name: "6-0-stable",
        maintenance_status: "security",
        enabled: true
      )

      gh_fetcher = instance_double(Github::BranchesFetcher)
      allow(Github::BranchesFetcher).to receive(:new).and_return(gh_fetcher)
      allow(gh_fetcher).to receive(:fetch_rails_stable_branches).with(repo: "rails/rails").and_return([
        Github::BranchesFetcher::BranchInfo.new(name: "main", protected: false, commit_sha: nil),
        Github::BranchesFetcher::BranchInfo.new(name: "7-2-stable", protected: false, commit_sha: nil)
      ])

      described_class.perform_now

      old_branch.reload
      expect(old_branch.maintenance_status).to eq("eol")
      expect(old_branch.enabled).to be false
    end

    it "creates a system event on success" do
      gh_fetcher = instance_double(Github::BranchesFetcher)
      allow(Github::BranchesFetcher).to receive(:new).and_return(gh_fetcher)
      allow(gh_fetcher).to receive(:fetch_rails_stable_branches).with(repo: "rails/rails").and_return([
        Github::BranchesFetcher::BranchInfo.new(name: "main", protected: false, commit_sha: nil)
      ])

      described_class.perform_now

      event = SystemEvent.where(kind: "branch_refresh").find { |e| e.payload["project"] == "rails" }
      expect(event).to be_present
      expect(event.status).to eq("ok")
      expect(event.message).to include("Rails")
    end

    it "handles fetch errors gracefully" do
      gh_fetcher = instance_double(Github::BranchesFetcher)
      allow(Github::BranchesFetcher).to receive(:new).and_return(gh_fetcher)
      allow(gh_fetcher).to receive(:fetch_rails_stable_branches).and_raise(
        Github::BranchesFetcher::FetchError.new("Failed to fetch branches for rails/rails: API error")
      )

      expect {
        described_class.perform_now
      }.to raise_error(Github::BranchesFetcher::FetchError)

      event = SystemEvent.where(kind: "branch_refresh").find { |e| e.payload["project"] == "rails" }
      expect(event).to be_present
      expect(event.status).to eq("failed")
    end
  end

  describe "project-scoped refresh" do
    let!(:rails_project) { create(:project, :rails) }

    before do
      # Mock both fetchers
      allow(RubyLang::MaintenanceBranches).to receive(:new).and_return(
        instance_double(RubyLang::MaintenanceBranches,
          fetch_html: "<html/>",
          parse_all_html: [RubyLang::MaintenanceBranches::Branch.new("3.4", "normal")]
        )
      )

      gh_fetcher = instance_double(Github::BranchesFetcher)
      allow(Github::BranchesFetcher).to receive(:new).and_return(gh_fetcher)
      allow(gh_fetcher).to receive(:fetch_rails_stable_branches).with(repo: "rails/rails").and_return([
        Github::BranchesFetcher::BranchInfo.new(name: "main", protected: false, commit_sha: nil)
      ])
    end

    it "refreshes only the specified project when project_slug is provided" do
      described_class.perform_now(project_slug: "rails")

      # Rails project should have been refreshed
      expect(rails_project.branch_targets.count).to eq(1)
      expect(rails_project.branch_targets.first.name).to eq("main")

      # Ruby project should NOT have been refreshed (no branches created)
      expect(ruby_project.branch_targets.count).to eq(0)
    end

    it "refreshes all enabled projects when no project_slug is provided" do
      described_class.perform_now

      # Both projects should have branch targets
      expect(ruby_project.branch_targets.count).to be >= 1
      expect(rails_project.branch_targets.count).to eq(1)
    end

    it "skips disabled projects" do
      disabled_project = create(:project, :mastodon, enabled: false)

      gh_fetcher = instance_double(Github::BranchesFetcher)
      allow(Github::BranchesFetcher).to receive(:new).and_return(gh_fetcher)
      allow(gh_fetcher).to receive(:fetch_rails_stable_branches).and_return([])

      described_class.perform_now

      expect(disabled_project.branch_targets.count).to eq(0)
    end
  end

  describe "manual branch discovery" do
    it "skips branch refresh and logs a system event" do
      manual_project = create(:project,
        name: "Manual Project",
        slug: "manual",
        upstream_repo: "org/manual",
        branch_discovery: "manual",
        enabled: true
      )

      described_class.perform_now(project_slug: "manual")

      event = SystemEvent.where(kind: "branch_refresh").find { |e| e.payload["project"] == "manual" }
      expect(event).to be_present
      expect(event.status).to eq("ok")
      expect(event.message).to include("Skipped")
      expect(event.message).to include("manual discovery")
    end
  end
end
