require "vcr"
require "webmock/rspec"

VCR.configure do |config|
  config.cassette_library_dir = Rails.root.join("spec", "vcr").to_s
  config.hook_into :webmock

  config.ignore_localhost = true

  config.default_cassette_options = {
    record: ENV.fetch("VCR_RECORD_MODE", "none").to_sym,
    match_requests_on: %i[method uri body]
  }

  config.filter_sensitive_data("<GH_TOKEN>") { ENV["GH_TOKEN"] }
  config.filter_sensitive_data("<GITHUB_TOKEN>") { ENV["GITHUB_TOKEN"] }
end
