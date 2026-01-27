class Admin::SystemEventsController < Admin::BaseController
  def index
    per_page = (params[:per_page].presence || 20).to_i.clamp(10, 100)
    @events = SystemEvent.order(occurred_at: :desc).page(params[:page]).per(per_page)
  end

  def show
    @event = SystemEvent.find(params[:id])
  end
end
