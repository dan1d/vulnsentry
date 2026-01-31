# frozen_string_literal: true

module Admin
  class ProjectsController < BaseController
    before_action :set_project, only: %i[show edit update refresh_branches]

    def index
      @projects = Project.order(:name)
    end

    def show
      @branch_targets = @project.branch_targets.order(:name)
      @recent_bundles = @project.patch_bundles.order(created_at: :desc).limit(10)
      @recent_prs = @project.pull_requests.order(created_at: :desc).limit(10)
    end

    def new
      @project = Project.new
    end

    def create
      @project = Project.new(project_params)

      if @project.save
        redirect_to admin_project_path(@project), notice: "Project was successfully created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @project.update(project_params)
        redirect_to admin_project_path(@project), notice: "Project was successfully updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def refresh_branches
      RefreshBranchTargetsJob.perform_later(project_slug: @project.slug)
      redirect_to admin_project_path(@project), notice: "Branch refresh started for #{@project.name}."
    end

    private

    def set_project
      @project = Project.find_by!(slug: params[:id])
    end

    def project_params
      params.require(:project).permit(
        :name,
        :slug,
        :upstream_repo,
        :fork_repo,
        :fork_git_url,
        :file_type,
        :file_path,
        :branch_discovery,
        :enabled
      )
    end
  end
end
