FactoryBot.define do
  factory :branch_target do
    sequence(:name) { |n| "ruby_3_#{n}" }
    enabled { true }
    maintenance_status { "normal" }
    source_url { "https://www.ruby-lang.org/en/downloads/branches/" }
    last_seen_at { Time.current }
  end
end
