class EvaluateOsvVulnerabilitiesJob < ApplicationJob
  queue_as :default

  # Evaluate vulnerabilities for all enabled projects.
  # @param project_slug [String, nil] Optional slug to limit to a single project
  # @param limit_branches [Integer, nil] Optional limit on branches per project
  def perform(project_slug: nil, limit_branches: nil)
    projects = if project_slug.present?
                 Project.enabled.where(slug: project_slug)
    else
                 Project.enabled
    end

    projects.find_each do |project|
      evaluate_project(project, limit_branches: limit_branches)
    end
  end

  private

  def evaluate_project(project, limit_branches:)
    branches = project.branch_targets
                      .where(enabled: true)
                      .where.not(maintenance_status: "eol")
                      .order(name: :asc)
    branches = branches.limit(limit_branches) if limit_branches

    evaluator = Evaluation::BundledGemsVulnerabilityEvaluator.new(project: project)

    branches.find_each do |branch_target|
      evaluator.evaluate_branch(branch_target)
    end

    SystemEvent.create!(
      kind: "project_evaluation",
      status: "ok",
      message: "Evaluated #{branches.count} branches for #{project.name}",
      payload: {
        project: project.slug,
        branches_evaluated: branches.count
      },
      occurred_at: Time.current
    )
  rescue StandardError => e
    SystemEvent.create!(
      kind: "project_evaluation",
      status: "failed",
      message: "Failed to evaluate #{project.name}: #{e.message}",
      payload: {
        project: project.slug,
        error: e.class.name,
        message: e.message
      },
      occurred_at: Time.current
    )
    raise
  end
end
