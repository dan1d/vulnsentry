class Admin::AdvisoriesController < Admin::BaseController
  def index
    per_page = (params[:per_page].presence || 20).to_i.clamp(10, 100)
    query = AdminQueries::AdvisoriesQuery.new.call(params)
    @advisories = query.page(params[:page]).per(per_page)
  end

  def show
    @advisory = Advisory.find(params[:id])
  end
end
