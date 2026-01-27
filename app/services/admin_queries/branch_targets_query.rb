module AdminQueries
  class BranchTargetsQuery
    def initialize(relation: BranchTarget.all)
      @relation = relation
    end

    def call(params)
      rel = @relation

      # Default to showing only "active" branches we actually evaluate:
      # enabled + non-EOL (normal/security). Older/EOL branches are still in the DB
      # for auditability, but don't need to clutter the main list view.
      if params[:enabled].blank? && params[:maintenance_status].blank?
        rel = rel.where(enabled: true, maintenance_status: %w[normal security])
      end

      if params[:enabled].present?
        rel = rel.where(enabled: ActiveModel::Type::Boolean.new.cast(params[:enabled]))
      end

      rel = rel.where(maintenance_status: params[:maintenance_status]) if params[:maintenance_status].present?
      rel.order(name: :asc)
    end
  end
end
