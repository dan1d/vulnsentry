class Admin::AdvisoriesController < Admin::BaseController
  def index
    query = AdminQueries::AdvisoriesQuery.new.call(params)
    @pagy, @advisories = pagy(query)
  end

  def show
    @advisory = Advisory.find(params[:id])
  end
end
