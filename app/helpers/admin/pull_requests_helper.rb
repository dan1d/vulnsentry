module Admin::PullRequestsHelper
  def pr_status_class(status)
    case status
    when "open"
      "is-success"
    when "merged"
      "is-link"
    when "closed"
      "is-danger"
    else
      "is-light"
    end
  end

  def pr_review_state_class(state)
    case state
    when "approved"
      "is-success"
    when "changes_requested"
      "is-warning"
    else
      "is-light"
    end
  end

  def severity_class(severity)
    case severity&.downcase
    when "critical", "high"
      "is-danger"
    when "medium", "moderate"
      "is-warning"
    when "low"
      "is-info"
    else
      "is-light"
    end
  end
end
