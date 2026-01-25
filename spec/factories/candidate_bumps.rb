FactoryBot.define do
  factory :candidate_bump do
    advisory
    branch_target
    base_branch { branch_target.name }
    gem_name { advisory.gem_name }
    current_version { "1.0.0" }
    target_version { "1.0.1" }
    state { "ready_for_review" }
  end
end
