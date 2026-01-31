require 'rails_helper'

RSpec.describe "Admin::BranchTargets", type: :request do
  describe "GET /admin/branch_targets" do
    it "lists branch targets" do
      create(:branch_target, name: "ruby_3_4", maintenance_status: "normal")
      sign_in_admin
      get "/admin/branch_targets"
      expect(response).to have_http_status(:success)
    end

    it "filters branch targets by enabled status" do
      project = create(:project)
      create(:branch_target, project: project, name: "ruby_3_4", maintenance_status: "normal", enabled: true)
      create(:branch_target, project: project, name: "ruby_3_2", maintenance_status: "security", enabled: false)

      sign_in_admin
      get "/admin/branch_targets", params: { enabled: "false" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("ruby_3_2")
      expect(response.body).not_to include("ruby_3_4")
    end

    describe "project filtering" do
      let!(:ruby_project) { create(:project, :ruby) }
      let!(:rails_project) { create(:project, :rails) }
      let!(:ruby_branch) { create(:branch_target, project: ruby_project, name: "ruby_3_4", maintenance_status: "normal") }
      let!(:rails_branch) { create(:branch_target, project: rails_project, name: "7-2-stable", maintenance_status: "normal") }

      before { sign_in_admin }

      it "shows all branches when no project filter is applied" do
        get "/admin/branch_targets"

        expect(response).to have_http_status(:success)
        expect(response.body).to include("ruby_3_4")
        expect(response.body).to include("7-2-stable")
      end

      it "filters branches by project_id" do
        get "/admin/branch_targets", params: { project_id: ruby_project.id }

        expect(response).to have_http_status(:success)
        expect(response.body).to include("ruby_3_4")
        expect(response.body).not_to include("7-2-stable")
      end

      it "filters to Rails project branches only" do
        get "/admin/branch_targets", params: { project_id: rails_project.id }

        expect(response).to have_http_status(:success)
        expect(response.body).to include("7-2-stable")
        expect(response.body).not_to include("ruby_3_4")
      end

      it "loads all projects for the dropdown" do
        get "/admin/branch_targets"

        expect(response.body).to include(ruby_project.name)
        expect(response.body).to include(rails_project.name)
      end

      it "maintains project filter in pagination" do
        # Create enough branches to paginate (using unique names)
        10.times { |i| create(:branch_target, project: ruby_project, name: "ruby_3_#{100 + i}", maintenance_status: "normal") }

        get "/admin/branch_targets", params: { project_id: ruby_project.id, per_page: 5 }

        expect(response).to have_http_status(:success)
        # All shown branches should be from Ruby project
        expect(response.body).not_to include("7-2-stable")
      end
    end

    describe "combined filtering" do
      let!(:ruby_project) { create(:project, :ruby) }
      let!(:rails_project) { create(:project, :rails) }

      before do
        create(:branch_target, project: ruby_project, name: "ruby_3_4", maintenance_status: "normal", enabled: true)
        create(:branch_target, project: ruby_project, name: "ruby_3_0", maintenance_status: "eol", enabled: false)
        create(:branch_target, project: rails_project, name: "7-2-stable", maintenance_status: "normal", enabled: true)
        create(:branch_target, project: rails_project, name: "6-0-stable", maintenance_status: "eol", enabled: false)
        sign_in_admin
      end

      it "filters by both project and enabled status" do
        get "/admin/branch_targets", params: { project_id: ruby_project.id, enabled: "false" }

        expect(response).to have_http_status(:success)
        expect(response.body).to include("ruby_3_0")
        expect(response.body).not_to include("ruby_3_4")
        expect(response.body).not_to include("7-2-stable")
        expect(response.body).not_to include("6-0-stable")
      end

      it "filters by project and maintenance status" do
        get "/admin/branch_targets", params: { project_id: rails_project.id, maintenance_status: "eol" }

        expect(response).to have_http_status(:success)
        expect(response.body).to include("6-0-stable")
        expect(response.body).not_to include("7-2-stable")
        expect(response.body).not_to include("ruby_3_0")
      end
    end
  end

  describe "GET /admin/branch_targets/:id/edit" do
    it "edits a branch target" do
      bt = create(:branch_target, name: "ruby_3_4", maintenance_status: "normal")
      sign_in_admin
      get "/admin/branch_targets/#{bt.id}/edit"
      expect(response).to have_http_status(:success)
    end
  end

  describe "PATCH /admin/branch_targets/:id" do
    it "updates a branch target" do
      bt = create(:branch_target, name: "ruby_3_4", maintenance_status: "normal", enabled: true)
      sign_in_admin
      patch "/admin/branch_targets/#{bt.id}", params: { branch_target: { enabled: false } }
      expect(response).to have_http_status(:redirect)
      expect(bt.reload.enabled).to be(false)
    end

    it "redirects back to the project-filtered list" do
      bt = create(:branch_target, name: "ruby_3_4", maintenance_status: "normal", enabled: true)
      sign_in_admin
      patch "/admin/branch_targets/#{bt.id}", params: { branch_target: { enabled: false } }

      expect(response).to redirect_to(admin_branch_targets_path(project_id: bt.project_id))
    end

    it "updates maintenance_status" do
      bt = create(:branch_target, name: "ruby_3_4", maintenance_status: "normal")
      sign_in_admin
      patch "/admin/branch_targets/#{bt.id}", params: { branch_target: { maintenance_status: "security" } }

      expect(bt.reload.maintenance_status).to eq("security")
    end

    it "renders edit form on invalid maintenance_status" do
      bt = create(:branch_target, name: "ruby_3_4", maintenance_status: "normal")
      sign_in_admin
      patch "/admin/branch_targets/#{bt.id}", params: { branch_target: { maintenance_status: "invalid" } }

      expect(response).to have_http_status(:unprocessable_entity)
      # Check page contains edit form elements
      expect(response.body).to include("Edit branch")
      expect(response.body).to include("branch_target[maintenance_status]")
    end
  end
end
