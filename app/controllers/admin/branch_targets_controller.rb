class Admin::BranchTargetsController < Admin::BaseController
  def index
    per_page = (params[:per_page].presence || 20).to_i.clamp(10, 100)

    # Support project filtering
    @projects = Project.order(:name)
    @selected_project = params[:project_id].present? ? Project.find_by(id: params[:project_id]) : nil

    query = AdminQueries::BranchTargetsQuery.new.call(params)

    # Filter by project if selected
    if @selected_project
      query = query.where(project_id: @selected_project.id)
    end

    @branch_targets = query.includes(:project).page(params[:page]).per(per_page)
  end

  def edit
    @branch_target = BranchTarget.find(params[:id])
  end

  def update
    @branch_target = BranchTarget.find(params[:id])
    if @branch_target.update(branch_target_params)
      redirect_to admin_branch_targets_path(project_id: @branch_target.project_id), notice: "Branch updated"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def branch_target_params
    params.require(:branch_target).permit(:enabled, :maintenance_status)
  end
end
