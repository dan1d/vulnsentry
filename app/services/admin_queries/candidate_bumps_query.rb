module AdminQueries
  class CandidateBumpsQuery
    def initialize(relation: CandidateBump.all)
      @relation = relation
    end

    def call(params)
      rel = @relation
        .joins(:branch_target)
        .where(branch_targets: { enabled: true })
        .where.not(branch_targets: { maintenance_status: "eol" })
        .includes(:pull_request)
      rel = rel.where(state: params[:state]) if params[:state].present?
      rel = rel.where(base_branch: params[:base_branch]) if params[:base_branch].present?
      rel = rel.where(gem_name: params[:gem_name]) if params[:gem_name].present?

      rel.order(created_at: :desc)
    end
  end
end
