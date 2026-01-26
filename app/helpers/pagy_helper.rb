module PagyHelper
  def pagy_nav(pagy)
    return "" unless pagy
    pagy.series_nav
  end
end
