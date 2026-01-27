module ApplicationHelper
  include PagyHelper

  # Brakeman warns when model-provided strings are used directly as hrefs.
  # Only allow http(s) URLs to prevent `javascript:` / `data:` style injection.
  def safe_http_url(url)
    return if url.blank?

    uri = URI.parse(url.to_s)
    return unless uri.scheme

    scheme = uri.scheme.downcase
    return unless scheme == "http" || scheme == "https"

    uri.to_s
  rescue URI::InvalidURIError
    nil
  end
end
