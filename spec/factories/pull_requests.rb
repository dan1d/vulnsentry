FactoryBot.define do
  factory :pull_request do
    candidate_bump
    upstream_repo { "ruby/ruby" }
    fork_repo { "dan1d/ruby" }
    head_branch { "bump-rexml-3.4.5-master" }
    sequence(:pr_number) { |n| 10_000 + n }
    pr_url { "https://github.com/ruby/ruby/pull/#{pr_number}" }
    status { "open" }
    opened_at { Time.current }

    trait :for_patch_bundle do
      candidate_bump { nil }
      patch_bundle
    end
  end
end
