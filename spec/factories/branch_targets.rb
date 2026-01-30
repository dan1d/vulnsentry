FactoryBot.define do
  factory :branch_target do
    project
    sequence(:name) { |n| "ruby_3_#{n}" }
    enabled { true }
    maintenance_status { "normal" }
    source_url { "https://www.ruby-lang.org/en/downloads/branches/" }
    last_seen_at { Time.current }

    trait :master do
      name { "master" }
    end

    trait :eol do
      maintenance_status { "eol" }
    end

    trait :security do
      maintenance_status { "security" }
    end
  end
end
