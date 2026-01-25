class RefreshBranchTargetsJob < ApplicationJob
  queue_as :default

  def perform
    fetcher = RubyLang::MaintenanceBranches.new
    supported = fetcher.fetch_supported

    upsert_supported(supported)
    ensure_master!
  end

  private
    def upsert_supported(branches)
      source_url = RubyLang::MaintenanceBranches::URL
      now = Time.current

      branches.each do |branch|
        name = "ruby_#{branch.series.tr('.', '_')}"
        row = BranchTarget.find_or_initialize_by(name: name)
        row.maintenance_status = branch.status
        row.source_url = source_url
        row.last_seen_at = now
        row.last_checked_at = now
        row.enabled = true if row.new_record? && row.enabled.nil?
        row.save!
      end
    end

    def ensure_master!
      now = Time.current
      row = BranchTarget.find_or_initialize_by(name: "master")
      row.maintenance_status ||= "normal"
      row.source_url ||= RubyLang::MaintenanceBranches::URL
      row.last_seen_at ||= now
      row.last_checked_at = now
      row.enabled = true if row.new_record? && row.enabled.nil?
      row.save!
    end
end

