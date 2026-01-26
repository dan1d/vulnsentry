require "pagy"
require "pagy/classes/request"
require "pagy/toolbox/paginators/offset"

# Pagy v43 is plain Ruby. We implement small Rails glue in:
# - `app/controllers/concerns/pagy_backend.rb`
# - `app/helpers/pagy_helper.rb`
