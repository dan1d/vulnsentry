class Admin::BranchTargetsController < Admin::BaseController
  def index
    per_page = (params[:per_page].presence || 20).to_i.clamp(10, 100)
    query = AdminQueries::BranchTargetsQuery.new.call(params)
    @branch_targets = query.page(params[:page]).per(per_page)
  end

  def edit
    @branch_target = BranchTarget.find(params[:id])
  end

  def update
    @branch_target = BranchTarget.find(params[:id])
    if @branch_target.update(branch_target_params)
      redirect_to admin_branch_targets_path, notice: "Branch updated"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private
    def branch_target_params
      params.require(:branch_target).permit(:enabled, :maintenance_status)
    end
end
