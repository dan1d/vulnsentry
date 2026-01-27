FactoryBot.define do
  factory :bundled_advisory do
    patch_bundle
    advisory
    suggested_fix_version { "3.2.7" }
    included_in_fix { true }

    trait :excluded do
      included_in_fix { false }
      exclusion_reason { "requires major version bump" }
    end

    trait :no_fix do
      suggested_fix_version { nil }
    end
  end
end
