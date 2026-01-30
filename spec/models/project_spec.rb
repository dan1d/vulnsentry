# frozen_string_literal: true

require "rails_helper"

RSpec.describe Project do
  describe "validations" do
    subject { build(:project) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:slug) }
    it { is_expected.to validate_presence_of(:upstream_repo) }
    it { is_expected.to validate_presence_of(:file_type) }
    it { is_expected.to validate_presence_of(:file_path) }
    it { is_expected.to validate_uniqueness_of(:slug) }
    it { is_expected.to validate_uniqueness_of(:upstream_repo) }
    it { is_expected.to validate_inclusion_of(:file_type).in_array(Project::FILE_TYPES) }
    it { is_expected.to validate_inclusion_of(:branch_discovery).in_array(Project::BRANCH_DISCOVERY_METHODS) }

    it "validates slug format" do
      project = build(:project, slug: "Invalid Slug!")
      expect(project).not_to be_valid
      expect(project.errors[:slug]).to include("must be lowercase alphanumeric with dashes/underscores")
    end

    it "validates upstream_repo format" do
      project = build(:project, upstream_repo: "invalid-format")
      expect(project).not_to be_valid
      expect(project.errors[:upstream_repo]).to include("must be in owner/repo format")
    end
  end

  describe "associations" do
    it { is_expected.to have_many(:branch_targets).dependent(:destroy) }
    it { is_expected.to have_many(:patch_bundles).through(:branch_targets) }
    it { is_expected.to have_many(:pull_requests).dependent(:nullify) }
  end

  describe "scopes" do
    describe ".enabled" do
      it "returns only enabled projects" do
        enabled = create(:project, :ruby)
        create(:project, :rails, enabled: false)

        expect(Project.enabled).to contain_exactly(enabled)
      end
    end
  end

  describe "#file_parser_class" do
    it "returns BundledGemsFile for bundled_gems type" do
      project = build(:project, file_type: "bundled_gems")
      expect(project.file_parser_class).to eq(ProjectFiles::BundledGemsFile)
    end

    it "returns GemfileLockFile for gemfile_lock type" do
      project = build(:project, file_type: "gemfile_lock")
      expect(project.file_parser_class).to eq(ProjectFiles::GemfileLockFile)
    end

    it "raises for unknown file type" do
      project = build(:project)
      project.instance_variable_set(:@file_type, "unknown")
      allow(project).to receive(:file_type).and_return("unknown")

      expect { project.file_parser_class }.to raise_error(ArgumentError, /Unknown file type/)
    end
  end

  describe "#can_create_prs?" do
    it "returns true when fork_repo and fork_git_url are present" do
      project = build(:project, fork_repo: "user/repo", fork_git_url: "git@github.com:user/repo.git")
      expect(project.can_create_prs?).to be true
    end

    it "returns false when fork_repo is missing" do
      project = build(:project, :without_fork)
      expect(project.can_create_prs?).to be false
    end
  end

  describe "#upstream_https_url" do
    it "returns the HTTPS clone URL" do
      project = build(:project, upstream_repo: "ruby/ruby")
      expect(project.upstream_https_url).to eq("https://github.com/ruby/ruby.git")
    end
  end

  describe "#parse_file" do
    it "returns a parser instance for the given content" do
      project = build(:project, file_type: "bundled_gems")
      content = "rexml 3.4.4 https://github.com/ruby/rexml\n"

      parser = project.parse_file(content)

      expect(parser).to be_a(ProjectFiles::BundledGemsFile)
      expect(parser.entries.first.name).to eq("rexml")
    end
  end

  describe "#to_param" do
    it "returns the slug" do
      project = build(:project, slug: "ruby")
      expect(project.to_param).to eq("ruby")
    end
  end
end
