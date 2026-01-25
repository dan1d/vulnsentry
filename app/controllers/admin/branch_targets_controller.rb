class Admin::BranchTargetsController < Admin::BaseController
  def index
    @branch_targets = BranchTarget.order(name: :asc)
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
