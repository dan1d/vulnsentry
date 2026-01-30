class SystemEventKinds
  # Return an array of distinct, non-empty kinds sorted alphabetically.
  # Cached in-memory for the process; call .clear_cache! to refresh.
  def self.all
    @kinds ||= begin
      SystemEvent.where.not(kind: [ nil, "" ]).distinct.pluck(:kind).compact.map(&:to_s).sort
    rescue StandardError
      []
    end
  end

  def self.options_for_select
    all.map { |k| [ k, k ] }
  end

  def self.clear_cache!
    @kinds = nil
  end
end
