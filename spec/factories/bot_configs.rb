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
    fork_repo { "dan1d/ruby" }
    upstream_repo { "ruby/ruby" }
    fork_git_url { "git@github.com:dan1d/ruby.git" }
  end
end
