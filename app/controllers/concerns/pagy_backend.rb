module PagyBackend
  extend ActiveSupport::Concern

  private
    def pagy(collection, limit: 50)
      pagy_request = Pagy::Request.new(request: request, limit: limit)
      Pagy::OffsetPaginator.paginate(collection, request: pagy_request)
    end
end
