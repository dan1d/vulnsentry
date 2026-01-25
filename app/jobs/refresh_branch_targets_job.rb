class RefreshBranchTargetsJob < ApplicationJob
  queue_as :default

  def perform
    fetcher = RubyLang::MaintenanceBranches.new
    html = fetcher.fetch_html
    supported = fetcher.parse_supported_html(html)

    cross_check_and_upsert!(html: html, supported: supported)
  end

  private
    def cross_check_and_upsert!(html:, supported:)
      cross = Ai::MaintenanceBranchesCrossCheck.new

      if cross.enabled?
        llm = cross.extract_branches!(html)
        cross.verify_match!(deterministic: supported, llm: llm)
      end

      ActiveRecord::Base.transaction do
        upsert_supported(supported)
        ensure_master!
      end

      SystemEvent.create!(kind: "branch_refresh", status: "ok", message: "updated branch targets", payload: { count: supported.count }, occurred_at: Time.current)
    rescue Ai::DeepseekClient::Error, Ai::MaintenanceBranchesCrossCheck::MismatchError, RubyLang::MaintenanceBranches::ParseError => e
      # Best practice: warn_and_freeze (do not change branches).
      SystemEvent.create!(
        kind: "branch_refresh",
        status: "failed",
        message: e.message,
        payload: { class: e.class.name, url: RubyLang::MaintenanceBranches::URL },
        occurred_at: Time.current
      )
      raise
    end

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
