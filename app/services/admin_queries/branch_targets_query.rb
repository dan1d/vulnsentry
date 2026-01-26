module AdminQueries
  class BranchTargetsQuery
    def initialize(relation: BranchTarget.all)
      @relation = relation
    end

    def call(params)
      rel = @relation
      if params[:enabled].present?
        rel = rel.where(enabled: ActiveModel::Type::Boolean.new.cast(params[:enabled]))
      end

      rel = rel.where(maintenance_status: params[:maintenance_status]) if params[:maintenance_status].present?
      rel.order(name: :asc)
    end
  end
end
