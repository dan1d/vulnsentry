class Admin::SystemEventsController < Admin::BaseController
  def index
    @events = SystemEvent.order(occurred_at: :desc).limit(200)
  end

  def show
    @event = SystemEvent.find(params[:id])
  end
end

