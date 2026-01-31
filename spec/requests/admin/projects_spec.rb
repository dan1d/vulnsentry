# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Projects", type: :request do
  describe "GET /admin/projects" do
    it "returns successful response" do
      sign_in_admin
      get "/admin/projects"
      expect(response).to be_successful
    end

    it "lists all projects" do
      ruby = create(:project, :ruby)
      rails = create(:project, :rails)
      sign_in_admin

      get "/admin/projects"

      expect(response.body).to include(ruby.name)
      expect(response.body).to include(rails.name)
    end

    it "shows project slugs" do
      create(:project, slug: "test-project", name: "Test", upstream_repo: "test/repo")
      sign_in_admin

      get "/admin/projects"

      expect(response.body).to include("test-project")
    end
  end

  describe "GET /admin/projects/:id" do
    let(:project) { create(:project, :ruby) }

    it "returns successful response" do
      sign_in_admin
      get "/admin/projects/#{project.slug}"
      expect(response).to be_successful
    end

    it "displays the project name" do
      sign_in_admin
      get "/admin/projects/#{project.slug}"
      expect(response.body).to include(project.name)
    end

    it "displays branch targets" do
      create(:branch_target, project: project, name: "master")
      sign_in_admin

      get "/admin/projects/#{project.slug}"

      expect(response.body).to include("master")
    end

    it "displays patch bundles" do
      branch = create(:branch_target, project: project)
      bundle = create(:patch_bundle, branch_target: branch, gem_name: "test-gem")
      sign_in_admin

      get "/admin/projects/#{project.slug}"

      expect(response.body).to include("test-gem")
    end

    it "displays pull requests" do
      branch = create(:branch_target, project: project)
      bundle = create(:patch_bundle, branch_target: branch)
      pr = create(:pull_request, :for_patch_bundle, patch_bundle: bundle, project: project, pr_number: 12345)
      sign_in_admin

      get "/admin/projects/#{project.slug}"

      expect(response.body).to include("12345")
    end
  end

  describe "GET /admin/projects/new" do
    it "returns successful response" do
      sign_in_admin
      get "/admin/projects/new"
      expect(response).to be_successful
    end

    it "displays new project form" do
      sign_in_admin
      get "/admin/projects/new"
      expect(response.body).to include("project[name]")
      expect(response.body).to include("project[slug]")
      expect(response.body).to include("project[upstream_repo]")
    end
  end

  describe "POST /admin/projects" do
    let(:valid_params) do
      {
        project: {
          name: "Test Project",
          slug: "test",
          upstream_repo: "test/test",
          file_type: "gemfile_lock",
          file_path: "Gemfile.lock",
          branch_discovery: "manual",
          enabled: true
        }
      }
    end

    it "creates a new project" do
      sign_in_admin
      expect {
        post "/admin/projects", params: valid_params
      }.to change(Project, :count).by(1)
    end

    it "redirects to show page on success" do
      sign_in_admin
      post "/admin/projects", params: valid_params
      expect(response).to redirect_to("/admin/projects/test")
    end

    it "returns unprocessable entity on validation error" do
      sign_in_admin
      post "/admin/projects", params: { project: { name: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "displays errors on validation failure" do
      sign_in_admin
      post "/admin/projects", params: { project: { name: "" } }
      expect(response.body).to include("can&#39;t be blank")
    end
  end

  describe "GET /admin/projects/:id/edit" do
    let(:project) { create(:project, :ruby) }

    it "returns successful response" do
      sign_in_admin
      get "/admin/projects/#{project.slug}/edit"
      expect(response).to be_successful
    end

    it "displays edit form with current values" do
      sign_in_admin
      get "/admin/projects/#{project.slug}/edit"
      expect(response.body).to include(project.name)
      expect(response.body).to include(project.upstream_repo)
    end
  end

  describe "PATCH /admin/projects/:id" do
    let(:project) { create(:project, :ruby) }

    it "updates the project" do
      sign_in_admin
      patch "/admin/projects/#{project.slug}", params: { project: { name: "Updated Name" } }

      project.reload
      expect(project.name).to eq("Updated Name")
    end

    it "redirects to show page on success" do
      sign_in_admin
      patch "/admin/projects/#{project.slug}", params: { project: { name: "Updated" } }
      expect(response).to redirect_to("/admin/projects/#{project.slug}")
    end

    it "returns unprocessable entity on validation error" do
      sign_in_admin
      patch "/admin/projects/#{project.slug}", params: { project: { name: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /admin/projects/:id/refresh_branches" do
    let(:project) { create(:project, :ruby) }

    it "enqueues a RefreshBranchTargetsJob" do
      sign_in_admin
      expect {
        post "/admin/projects/#{project.slug}/refresh_branches"
      }.to have_enqueued_job(RefreshBranchTargetsJob).with(project_slug: project.slug)
    end

    it "redirects to show page with notice" do
      sign_in_admin
      post "/admin/projects/#{project.slug}/refresh_branches"

      expect(response).to redirect_to("/admin/projects/#{project.slug}")
      expect(flash[:notice]).to include("Branch refresh started")
    end
  end
end
