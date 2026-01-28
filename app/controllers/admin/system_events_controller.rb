class Admin::SystemEventsController < Admin::BaseController
  def index
    per_page = (params[:per_page].presence || 20).to_i.clamp(10, 100)
    query = AdminQueries::SystemEventsQuery.new.call(params)
    @events = query.page(params[:page]).per(per_page)
  end

  def show
    @event = SystemEvent.find(params[:id])
  end
end
