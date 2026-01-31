FactoryBot.define do
  factory :bot_config do
    singleton { true }
    require_human_approval { true }
    emergency_stop { false }
    allow_draft_pr { false }
    global_daily_cap { 3 }
    global_hourly_cap { 1 }
    per_branch_daily_cap { 1 }
    per_gem_daily_cap { 1 }
    rejection_cooldown_hours { 24 }
    # Note: fork_repo, upstream_repo, and fork_git_url are now read-only
    # and delegate to the default project. Create a project factory first
    # if you need these values.
  end
end
