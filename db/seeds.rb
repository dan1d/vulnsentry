if Rails.env.production?
  # Keep production seeds intentionally minimal.
  BotConfig.instance
  puts "Seeded BotConfig singleton."
  return
end

unless defined?(FactoryBot)
  puts "FactoryBot is required for development seeds."
  puts "Run with the development group enabled (default for local dev)."
  return
end

puts "Seeding development data..."

FactoryBot.find_definitions

seed_user = ENV.fetch("SEED_ADMIN_USER", "dan1d")
seed_password = ENV.fetch("SEED_ADMIN_PASSWORD", "password")

AdminUser.find_by(username: seed_user)&.destroy!
admin = FactoryBot.create(
  :admin_user,
  username: seed_user,
  password: seed_password,
  password_confirmation: seed_password
)
puts "Created AdminUser: #{admin.username} (password from SEED_ADMIN_PASSWORD or default)."

BotConfig.instance

BranchTarget.delete_all
Advisory.delete_all
CandidateBump.delete_all
PullRequest.delete_all
SystemEvent.delete_all

master = FactoryBot.create(:branch_target, name: "master", maintenance_status: "normal", enabled: true)
ruby_3_4 = FactoryBot.create(:branch_target, name: "ruby_3_4", maintenance_status: "normal", enabled: true)
ruby_3_3 = FactoryBot.create(:branch_target, name: "ruby_3_3", maintenance_status: "security", enabled: true)
FactoryBot.create(:branch_target, name: "ruby_3_2", maintenance_status: "security", enabled: false)

advisory_rexml = FactoryBot.create(
  :advisory,
  source: "ruby_lang",
  gem_name: "rexml",
  cve: "CVE-2026-0001",
  fixed_version: "3.3.9",
  advisory_url: "https://www.ruby-lang.org/en/news/"
)

advisory_rake = FactoryBot.create(
  :advisory,
  source: "ghsa",
  gem_name: "rake",
  cve: "CVE-2026-0002",
  fixed_version: "13.2.0",
  advisory_url: "https://github.com/advisories"
)

advisory_uri = FactoryBot.create(
  :advisory,
  source: "osv",
  gem_name: "uri",
  cve: "CVE-2026-0003",
  fixed_version: "0.13.2",
  advisory_url: "https://osv.dev/"
)

FactoryBot.create(
  :candidate_bump,
  advisory: advisory_rexml,
  branch_target: ruby_3_4,
  base_branch: ruby_3_4.name,
  current_version: "3.3.8",
  target_version: "3.3.9",
  state: "ready_for_review",
  proposed_diff: "- rexml (3.3.8)\n+ rexml (3.3.9)\n"
)

cb_approved = FactoryBot.create(
  :candidate_bump,
  advisory: advisory_rake,
  branch_target: ruby_3_3,
  base_branch: ruby_3_3.name,
  current_version: "13.1.0",
  target_version: "13.2.0",
  state: "approved",
  approved_at: Time.current,
  approved_by: admin.username,
  proposed_diff: "- rake (13.1.0)\n+ rake (13.2.0)\n"
)

FactoryBot.create(
  :candidate_bump,
  advisory: advisory_uri,
  branch_target: master,
  base_branch: master.name,
  current_version: "0.13.0",
  target_version: "0.13.2",
  state: "rejected",
  blocked_reason: "rejected_by_admin",
  proposed_diff: "- uri (0.13.0)\n+ uri (0.13.2)\n"
)

FactoryBot.create(
  :pull_request,
  candidate_bump: cb_approved,
  status: "open",
  head_branch: "bump-rake-13.2.0-#{ruby_3_3.name}",
  pr_url: "https://github.com/ruby/ruby/pull/12345"
)

merged_cb = FactoryBot.create(
  :candidate_bump,
  advisory: advisory_rexml,
  branch_target: master,
  base_branch: master.name,
  current_version: "3.3.8",
  target_version: "3.3.9",
  state: "submitted",
  proposed_diff: "- rexml (3.3.8)\n+ rexml (3.3.9)\n"
)
FactoryBot.create(
  :pull_request,
  candidate_bump: merged_cb,
  status: "merged",
  pr_number: 12_346,
  pr_url: "https://github.com/ruby/ruby/pull/12346",
  merged_at: 2.days.ago,
  head_branch: "bump-rexml-3.3.9-#{master.name}"
)

SystemEvent.create!(
  kind: "seed",
  status: "ok",
  message: "Development seed data loaded",
  occurred_at: Time.current
)

SystemEvent.create!(
  kind: "evaluation",
  status: "warning",
  message: "Example: OSV request timed out (seed)",
  occurred_at: 3.hours.ago
)

SystemEvent.create!(
  kind: "pr_creation",
  status: "failed",
  message: "Example: branch already exists in fork (seed)",
  occurred_at: 1.hour.ago
)

puts "Seed complete."
