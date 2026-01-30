# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::ProjectsController do
  let(:admin) { create(:admin_user) }

  before do
    sign_in admin
  end

  describe "GET #index" do
    it "returns successful response" do
      get :index
      expect(response).to be_successful
    end

    it "lists all projects" do
      ruby = create(:project, :ruby)
      rails = create(:project, :rails)

      get :index

      expect(assigns(:projects)).to include(ruby, rails)
    end
  end

  describe "GET #show" do
    let(:project) { create(:project, :ruby) }

    it "returns successful response" do
      get :show, params: { id: project.slug }
      expect(response).to be_successful
    end

    it "loads the project by slug" do
      get :show, params: { id: project.slug }
      expect(assigns(:project)).to eq(project)
    end

    it "loads branch targets" do
      create(:branch_target, project: project, name: "master")

      get :show, params: { id: project.slug }

      expect(assigns(:branch_targets).count).to eq(1)
    end
  end

  describe "GET #new" do
    it "returns successful response" do
      get :new
      expect(response).to be_successful
    end

    it "builds a new project" do
      get :new
      expect(assigns(:project)).to be_a_new(Project)
    end
  end

  describe "POST #create" do
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
      expect {
        post :create, params: valid_params
      }.to change(Project, :count).by(1)
    end

    it "redirects to show page on success" do
      post :create, params: valid_params
      expect(response).to redirect_to(admin_project_path("test"))
    end

    it "renders new on validation error" do
      post :create, params: { project: { name: "" } }
      expect(response).to render_template(:new)
    end
  end

  describe "GET #edit" do
    let(:project) { create(:project, :ruby) }

    it "returns successful response" do
      get :edit, params: { id: project.slug }
      expect(response).to be_successful
    end
  end

  describe "PATCH #update" do
    let(:project) { create(:project, :ruby) }

    it "updates the project" do
      patch :update, params: { id: project.slug, project: { name: "Updated Name" } }

      project.reload
      expect(project.name).to eq("Updated Name")
    end

    it "redirects to show page on success" do
      patch :update, params: { id: project.slug, project: { name: "Updated" } }
      expect(response).to redirect_to(admin_project_path(project))
    end

    it "renders edit on validation error" do
      patch :update, params: { id: project.slug, project: { name: "" } }
      expect(response).to render_template(:edit)
    end
  end
end
