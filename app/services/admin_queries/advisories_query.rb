module AdminQueries
  class AdvisoriesQuery
    def initialize(relation: Advisory.all)
      @relation = relation
    end

    def call(params)
      rel = @relation
      rel = rel.where(source: params[:source]) if params[:source].present?
      rel = rel.where(gem_name: params[:gem_name]) if params[:gem_name].present?
      rel = rel.where(cve: params[:cve]) if params[:cve].present?

      if params[:q].present?
        q = "%#{params[:q]}%"
        rel = rel.where(
          "fingerprint ILIKE ? OR advisory_url ILIKE ? OR cve ILIKE ? OR gem_name ILIKE ?",
          q, q, q, q
        )
      end

      rel.order(created_at: :desc)
    end
  end
end
