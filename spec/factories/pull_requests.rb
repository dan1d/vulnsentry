FactoryBot.define do
  factory :pull_request do
    candidate_bump
    upstream_repo { "ruby/ruby" }
    sequence(:pr_number) { |n| 10_000 + n }
    pr_url { "https://github.com/ruby/ruby/pull/#{pr_number}" }
    status { "open" }
    opened_at { Time.current }
  end
end
