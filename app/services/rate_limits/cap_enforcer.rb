module RateLimits
  class CapEnforcer
    Result = Data.define(:allowed, :reason, :next_eligible_at)

    def initialize(config: BotConfig.instance, now: Time.current)
      @config = config
      @now = now
    end

    def check!(gem_name:, base_branch:)
      return Result.new(false, "emergency_stop", nil) if @config.emergency_stop?

      cooldown_result = check_rejection_cooldown(gem_name: gem_name, base_branch: base_branch)
      return cooldown_result if cooldown_result

      hourly = @config.global_hourly_cap
      if hourly && hourly > 0
        count = PullRequest.where("created_at >= ?", @now - 1.hour).count
        return blocked("global_hourly_cap", next_window_time(1.hour)) if count >= hourly
      end

      daily = @config.global_daily_cap
      if daily && daily > 0
        count = PullRequest.where("created_at >= ?", @now - 1.day).count
        return blocked("global_daily_cap", next_window_time(1.day)) if count >= daily
      end

      per_branch = @config.per_branch_daily_cap
      if per_branch && per_branch > 0
        count = PullRequest.joins(:candidate_bump).where(candidate_bumps: { base_branch: base_branch })
          .where("pull_requests.created_at >= ?", @now - 1.day).count
        return blocked("per_branch_daily_cap", next_window_time(1.day)) if count >= per_branch
      end

      per_gem = @config.per_gem_daily_cap
      if per_gem && per_gem > 0
        count = PullRequest.joins(:candidate_bump).where(candidate_bumps: { gem_name: gem_name })
          .where("pull_requests.created_at >= ?", @now - 1.day).count
        return blocked("per_gem_daily_cap", next_window_time(1.day)) if count >= per_gem
      end

      Result.new(true, nil, nil)
    end

    private
      def blocked(reason, next_eligible_at)
        Result.new(false, reason, next_eligible_at)
      end

      def next_window_time(window)
        @now + window
      end

      def check_rejection_cooldown(gem_name:, base_branch:)
        hours = @config.rejection_cooldown_hours.to_i
        return nil if hours <= 0

        cutoff = @now - hours.hours
        recent = CandidateBump.where(gem_name: gem_name, base_branch: base_branch, state: %w[rejected failed])
          .where("updated_at >= ?", cutoff)
          .order(updated_at: :desc)
          .first
        return nil unless recent

        blocked("cooldown", recent.updated_at + hours.hours)
      end
  end
end
