FactoryBot.define do
  factory :patch_bundle do
    branch_target
    base_branch { branch_target.name }
    gem_name { "rexml" }
    current_version { "3.2.5" }
    target_version { "3.2.7" }
    state { "ready_for_review" }
    resolution_source { "auto" }

    trait :awaiting_fix do
      state { "awaiting_fix" }
      target_version { nil }
      blocked_reason { "no_fixed_version_available" }
    end

    trait :needs_review do
      state { "needs_review" }
      resolution_source { "llm" }
      llm_recommendation do
        {
          "recommended_version" => "3.2.7",
          "confidence" => "low",
          "reasoning" => "Mixed version requirements"
        }
      end
    end

    trait :approved do
      state { "approved" }
      approved_at { Time.current }
      approved_by { "admin" }
    end

    trait :submitted do
      state { "submitted" }
      created_pr_at { Time.current }
    end

    trait :with_advisories do
      transient do
        advisories_count { 2 }
      end

      after(:create) do |bundle, evaluator|
        evaluator.advisories_count.times do
          advisory = create(:advisory, gem_name: bundle.gem_name)
          create(:bundled_advisory, patch_bundle: bundle, advisory: advisory)
        end
      end
    end
  end
end
