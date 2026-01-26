module AdminQueries
  class PullRequestsQuery
    def initialize(relation: PullRequest.all)
      @relation = relation
    end

    def call(params)
      rel = @relation
      rel = rel.where(status: params[:status]) if params[:status].present?
      rel = rel.where(upstream_repo: params[:upstream_repo]) if params[:upstream_repo].present?

      if params[:base_branch].present?
        rel = rel.joins(:candidate_bump).where(candidate_bumps: { base_branch: params[:base_branch] })
      end

      rel.order(created_at: :desc)
    end
  end
end
