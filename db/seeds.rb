if Rails.env.production?
  # Keep production seeds intentionally minimal.
  BotConfig.instance
  puts "Seeded BotConfig singleton."
  return
end

begin
  require "factory_bot_rails"
  require "faker"
rescue LoadError
  puts "FactoryBot/Faker are required for development seeds."
  puts "Run with the development group enabled (default for local dev)."
  return
end

puts "Seeding development data..."

if FactoryBot.respond_to?(:reload)
  FactoryBot.reload
else
  FactoryBot.find_definitions
end

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

BotConfig.instance.update!(emergency_stop: true)
puts "BotConfig.emergency_stop is ON (seed safety)."

PullRequest.delete_all
CandidateBump.delete_all
Advisory.delete_all
BranchTarget.delete_all
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

# Extra advisories for pagination / filtering
seed_gems = %w[
  rexml
  rake
  uri
  openssl
  net-http
  json
  psych
  webrick
  logger
  csv
  date
  stringio
]
sources = %w[ruby_lang ghsa osv]
140.times do |i|
  gem_name = seed_gems[i % seed_gems.length]
  source = sources[i % sources.length]
  cve = format("CVE-2026-%04d", 100 + i)
  fixed = "1.#{(i % 9) + 1}.#{(i % 20) + 1}"

  FactoryBot.create(
    :advisory,
    source: source,
    gem_name: gem_name,
    cve: cve,
    fixed_version: fixed,
    advisory_url: "https://example.test/#{source}/#{cve}"
  )
end

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

# More events for pagination
60.times do |i|
  SystemEvent.create!(
    kind: "seed",
    status: %w[ok warning failed][i % 3],
    message: "Seed event ##{i + 1}",
    occurred_at: (i + 1).minutes.ago
  )
end

# More candidates + PRs for pagination (DB records only; no GitHub calls)
advisories = Advisory.order(created_at: :desc).limit(80).to_a
branches = BranchTarget.where(enabled: true).to_a
states = %w[
  pending
  blocked_rate_limited
  blocked_ambiguous
  ready_for_review
  approved
  rejected
  submitted
  failed
]

120.times do |i|
  advisory = advisories[i % advisories.length]
  branch = branches[i % branches.length]
  state = states[i % states.length]

  bump = FactoryBot.create(
    :candidate_bump,
    advisory: advisory,
    branch_target: branch,
    base_branch: branch.name,
    current_version: "1.0.#{i % 5}",
    target_version: "1.0.#{(i % 5) + 1}",
    state: state,
    approved_at: (state == "approved" ? Time.current : nil),
    approved_by: (state == "approved" ? admin.username : nil),
    blocked_reason: (state.start_with?("blocked") ? "seeded_#{state}" : nil),
    proposed_diff: "- #{advisory.gem_name} (1.0.#{i % 5})\n+ #{advisory.gem_name} (1.0.#{(i % 5) + 1})\n"
  )

  pr_status = %w[open closed merged][i % 3]
  FactoryBot.create(
    :pull_request,
    candidate_bump: bump,
    status: pr_status,
    pr_number: 20_000 + i,
    pr_url: "https://github.com/ruby/ruby/pull/#{20_000 + i}",
    opened_at: 10.days.ago,
    closed_at: (pr_status == "closed" ? 5.days.ago : nil),
    merged_at: (pr_status == "merged" ? 4.days.ago : nil),
    head_branch: "bump-#{bump.gem_name}-#{bump.target_version}-#{branch.name}"
  )
end

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
