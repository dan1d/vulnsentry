require "rails_helper"

RSpec.describe BranchTarget, type: :model do
  subject(:branch_target) { build(:branch_target) }

  describe "associations" do
    it { is_expected.to belong_to(:project) }
    it { is_expected.to have_many(:candidate_bumps).dependent(:destroy) }
    it { is_expected.to have_many(:patch_bundles).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:maintenance_status) }
    it { is_expected.to validate_inclusion_of(:maintenance_status).in_array(described_class::MAINTENANCE_STATUSES) }

    describe "uniqueness of name within project scope" do
      let(:project) { create(:project) }
      let!(:existing_branch) { create(:branch_target, project: project, name: "master") }

      it "allows same branch name in different projects" do
        other_project = create(:project, slug: "other", upstream_repo: "other/repo")
        new_branch = build(:branch_target, project: other_project, name: "master")
        expect(new_branch).to be_valid
      end

      it "rejects duplicate branch name in same project" do
        duplicate = build(:branch_target, project: project, name: "master")
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:name]).to include("must be unique within project")
      end
    end
  end

  describe "scopes" do
    let(:project) { create(:project) }

    describe ".enabled" do
      it "returns only enabled branch targets" do
        enabled = create(:branch_target, project: project, enabled: true)
        create(:branch_target, project: project, name: "disabled", enabled: false)

        expect(described_class.enabled).to contain_exactly(enabled)
      end
    end

    describe ".active" do
      it "returns enabled, non-EOL branch targets" do
        normal = create(:branch_target, project: project, maintenance_status: "normal", enabled: true)
        security = create(:branch_target, project: project, name: "security_branch", maintenance_status: "security", enabled: true)
        create(:branch_target, project: project, name: "eol_branch", maintenance_status: "eol", enabled: false)
        create(:branch_target, project: project, name: "disabled_branch", maintenance_status: "normal", enabled: false)

        expect(described_class.active).to contain_exactly(normal, security)
      end
    end
  end

  describe "delegated methods" do
    let(:project) { create(:project, upstream_repo: "test/repo", fork_repo: "fork/repo") }
    let(:branch) { create(:branch_target, project: project) }

    it "delegates upstream_repo to project" do
      expect(branch.upstream_repo).to eq("test/repo")
    end

    it "delegates fork_repo to project" do
      expect(branch.fork_repo).to eq("fork/repo")
    end
  end

  describe "status methods" do
    let(:project) { create(:project) }

    describe "#eol?" do
      it "returns true when maintenance_status is eol" do
        branch = build(:branch_target, project: project, maintenance_status: "eol")
        expect(branch.eol?).to be true
      end

      it "returns false when maintenance_status is not eol" do
        branch = build(:branch_target, project: project, maintenance_status: "normal")
        expect(branch.eol?).to be false
      end
    end

    describe "#security_only?" do
      it "returns true when maintenance_status is security" do
        branch = build(:branch_target, project: project, maintenance_status: "security")
        expect(branch.security_only?).to be true
      end

      it "returns false when maintenance_status is not security" do
        branch = build(:branch_target, project: project, maintenance_status: "normal")
        expect(branch.security_only?).to be false
      end
    end

    describe "#normal?" do
      it "returns true when maintenance_status is normal" do
        branch = build(:branch_target, project: project, maintenance_status: "normal")
        expect(branch.normal?).to be true
      end

      it "returns false when maintenance_status is not normal" do
        branch = build(:branch_target, project: project, maintenance_status: "security")
        expect(branch.normal?).to be false
      end
    end
  end
end
