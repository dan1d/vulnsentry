# frozen_string_literal: true

# Concern for caching external API responses using Rails.cache.
#
# Provides a standardized caching pattern for API clients with:
# - Configurable TTL per cache type
# - Cache key namespacing
# - Automatic cache invalidation support
# - Logging for cache hits/misses
#
# Usage:
#   class Osv::Client
#     include CacheableApi
#
#     def query_rubygems(gem_name:, version:)
#       cached(:osv_query, gem_name, version, expires_in: 1.hour) do
#         # actual API call
#       end
#     end
#   end
#
module CacheableApi
  extend ActiveSupport::Concern

  # Default cache TTLs for different API types
  CACHE_TTLS = {
    osv_query: 1.hour,
    ghsa_query: 15.minutes,
    bundled_gems: 30.minutes,
    ruby_lang_rss: 1.hour
  }.freeze

  included do
    class_attribute :cache_enabled, default: true
    class_attribute :cache_namespace, default: "api"
  end

  class_methods do
    def disable_cache!
      self.cache_enabled = false
    end

    def enable_cache!
      self.cache_enabled = true
    end
  end

  private

  # Fetches from cache or executes block, storing result.
  #
  # @param cache_type [Symbol] Type of cache (determines default TTL)
  # @param key_parts [Array] Parts to build the cache key
  # @param expires_in [ActiveSupport::Duration] Override default TTL
  # @param force [Boolean] Bypass cache and force fresh fetch
  # @return [Object] Cached or freshly fetched result
  def cached(cache_type, *key_parts, expires_in: nil, force: false)
    return yield unless cache_enabled

    cache_key = build_cache_key(cache_type, *key_parts)
    ttl = expires_in || CACHE_TTLS.fetch(cache_type, 1.hour)

    if force
      result = yield
      Rails.cache.write(cache_key, result, expires_in: ttl)
      log_cache_event(:force_refresh, cache_key)
      result
    else
      Rails.cache.fetch(cache_key, expires_in: ttl) do
        log_cache_event(:miss, cache_key)
        yield
      end
    end
  end

  # Invalidates a specific cache entry.
  #
  # @param cache_type [Symbol] Type of cache
  # @param key_parts [Array] Parts to build the cache key
  def invalidate_cache(cache_type, *key_parts)
    cache_key = build_cache_key(cache_type, *key_parts)
    Rails.cache.delete(cache_key)
    log_cache_event(:invalidate, cache_key)
  end

  # Builds a namespaced cache key.
  #
  # @param cache_type [Symbol] Type of cache
  # @param key_parts [Array] Parts to build the cache key
  # @return [String] The complete cache key
  def build_cache_key(cache_type, *key_parts)
    parts = [ cache_namespace, cache_type, *key_parts ].map(&:to_s)
    parts.join("/")
  end

  def log_cache_event(event, cache_key)
    return unless Rails.logger.debug?

    Rails.logger.debug { "[CacheableApi] #{event}: #{cache_key}" }
  end
end
