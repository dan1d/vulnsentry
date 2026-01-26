class Admin::BaseController < ApplicationController
  include PagyBackend

  before_action :require_admin!
end
