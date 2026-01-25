class EvaluateOsvVulnerabilitiesJob < ApplicationJob
  queue_as :default

  def perform(limit_branches: nil)
    branches = BranchTarget.where(enabled: true).order(name: :asc)
    branches = branches.limit(limit_branches) if limit_branches

    evaluator = Evaluation::BundledGemsVulnerabilityEvaluator.new

    branches.find_each do |branch_target|
      evaluator.evaluate_branch(branch_target)
    end
  end
end
