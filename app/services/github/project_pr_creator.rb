# frozen_string_literal: true

require "open3"
require "tmpdir"

module Github
  # Creates PRs for any project by using project-specific configuration.
  # Supports different file types (bundled_gems, gemfile_lock) through
  # the project's file parser.
  class ProjectPrCreator
    class Error < StandardError; end

    def initialize(project:, gh: GhCli.new)
      @project = project
      @gh = gh
    end

    # Creates a PR for a PatchBundle
    def create_for_patch_bundle!(bundle, draft: false)
      raise Error, "bundle not approved" unless bundle.state == "approved"
      raise Error, "bundle already has PR" if bundle.pull_request.present?
      raise Error, "bundle has no target version" unless bundle.has_fix?
      raise Error, "project cannot create PRs (no fork configured)" unless @project.can_create_prs?

      base_branch = bundle.base_branch
      branch_name = branch_name_for_bundle(bundle)

      Dir.mktmpdir("project-pr-") do |dir|
        repo_dir = File.join(dir, "repo")
        clone_upstream!(dir, repo_dir, base_branch)
        configure_git_identity!(repo_dir)
        create_branch!(repo_dir, branch_name)

        apply_bundle_bump!(repo_dir, bundle)
        commit!(repo_dir, commit_message_for_bundle(bundle))
        branch_name = ensure_unique_head_branch!(repo_dir, branch_name)
        push_to_fork!(repo_dir, branch_name)

        pr = ensure_pr_for_bundle!(branch_name, base_branch, bundle, draft: draft)
        { number: pr.fetch("number"), url: pr.fetch("url"), head_branch: branch_name }
      end
    end

    private

    def clone_upstream!(work_dir, repo_dir, base_branch)
      run_git!(
        "clone",
        "--depth",
        "1",
        "--branch",
        base_branch,
        @project.upstream_https_url,
        repo_dir,
        dir: work_dir
      )
      within_repo(repo_dir) { run_git!("remote", "add", "fork", fork_git_url) }
    end

    def configure_git_identity!(repo_dir)
      within_repo(repo_dir) do
        run_git!("config", "user.name", "VulnSentry Bot")
        run_git!("config", "user.email", "vulnsentry-bot@users.noreply.github.com")
      end
    end

    def create_branch!(repo_dir, branch_name)
      within_repo(repo_dir) { run_git!("checkout", "-b", branch_name) }
    end

    def apply_bundle_bump!(repo_dir, bundle)
      file_path = File.join(repo_dir, @project.file_path)
      old_content = File.read(file_path)

      result = apply_bump_for_file_type(old_content, bundle)

      # Validate against proposed diff if present
      expected = bundle.proposed_diff.to_s.strip
      actual = "-#{result.fetch(:old_line).rstrip}\n+#{result.fetch(:new_line).rstrip}"
      unless expected.blank? || expected == actual
        raise Error, "proposed diff mismatch (refuse to proceed)"
      end

      File.write(file_path, result.fetch(:new_content))

      within_repo(repo_dir) do
        diff = run_git!("diff", "--name-only").strip
        raise Error, "unexpected diff files: #{diff.inspect}" unless diff == @project.file_path
      end
    end

    def apply_bump_for_file_type(old_content, bundle)
      case @project.file_type
      when "bundled_gems"
        apply_bundled_gems_bump(old_content, bundle)
      when "gemfile_lock"
        apply_gemfile_lock_bump(old_content, bundle)
      else
        raise Error, "unsupported file type: #{@project.file_type}"
      end
    end

    def apply_bundled_gems_bump(old_content, bundle)
      begin
        RubyCore::BundledGemsBumper.bump!(
          old_content: old_content,
          gem_name: bundle.gem_name,
          target_version: bundle.target_version
        )
      rescue RubyCore::BundledGemsFile::ParseError => e
        assistant = Ai::BundledGemsBumpAssistant.new
        raise Error, e.message unless assistant.enabled?

        assistant.suggest_bump!(
          old_content: old_content,
          gem_name: bundle.gem_name,
          target_version: bundle.target_version
        )
      end
    end

    def apply_gemfile_lock_bump(old_content, bundle)
      # For Gemfile.lock, we use the ProjectFiles parser
      file = ProjectFiles::GemfileLockFile.new(old_content)
      new_content, old_line, new_line = file.bump_version!(bundle.gem_name, bundle.target_version)
      { new_content: new_content, old_line: old_line, new_line: new_line }
    end

    def commit!(repo_dir, message)
      within_repo(repo_dir) do
        run_git!("add", @project.file_path)
        run_git!("commit", "-m", message)
      end
    end

    def ensure_unique_head_branch!(repo_dir, branch_name)
      return branch_name unless remote_branch_exists?(repo_dir, branch_name)

      existing = pr_view(@project.upstream_repo, "#{fork_owner}:#{branch_name}")
      return branch_name if existing

      2.upto(10) do |n|
        alt = "#{branch_name}-#{n}"
        next if remote_branch_exists?(repo_dir, alt)

        existing_alt = pr_view(@project.upstream_repo, "#{fork_owner}:#{alt}")
        return alt if existing_alt

        within_repo(repo_dir) { run_git!("branch", "-m", alt) }
        return alt
      end

      raise Error, "unable to find unique branch name"
    end

    def push_to_fork!(repo_dir, branch_name)
      within_repo(repo_dir) do
        run_git!(
          "push",
          "fork",
          "HEAD:refs/heads/#{branch_name}",
          env: git_env
        )
      end
    end

    def ensure_pr_for_bundle!(branch_name, base_branch, bundle, draft:)
      upstream = @project.upstream_repo
      head = "#{fork_owner}:#{branch_name}"

      existing = pr_view(upstream, head)
      return existing if existing

      title = pr_title_for_bundle(bundle)
      body = pr_body_for_bundle(bundle)

      args = [ "pr", "create", "--repo", upstream, "--head", head, "--base", base_branch, "--title", title, "--body", body ]
      args << "--draft" if draft

      url = @gh.run!(*args).strip
      pr = @gh.json!("pr", "view", "--repo", upstream, url, "--json", "number,url,state")
      pr.merge("url" => pr.fetch("url"))
    end

    def pr_view(upstream, head)
      prs = @gh.json!("pr", "list", "--repo", upstream, "--head", head, "--json", "number,url,state", "--limit", "1")
      return nil unless prs.is_a?(Array)
      prs.first
    rescue Github::GhCli::CommandError
      nil
    end

    def pr_title_for_bundle(bundle)
      target = branch_display_name(bundle.base_branch)
      "Bump #{bundle.gem_name} to #{bundle.target_version} for #{target}"
    end

    def pr_body_for_bundle(bundle)
      lines = []
      lines << "## Summary"
      lines << "- Security bump for dependency `#{bundle.gem_name}` in #{@project.name}."
      lines << "- Scope: version bump only (`#{@project.file_path}`)."
      lines << ""
      lines << "## Security Advisories Addressed"
      lines << ""

      bundle.bundled_advisories.includes(:advisory).each do |ba|
        next unless ba.included_in_fix?
        advisory = ba.advisory
        cve = advisory.cve.presence || advisory.fingerprint
        url = advisory.advisory_url
        if url.present?
          lines << "- [#{cve}](#{url}) (#{advisory.source})"
        else
          lines << "- #{cve} (#{advisory.source})"
        end
      end

      lines << ""
      lines << "---"
      lines << "_This PR was created automatically by [VulnSentry](https://github.com/dan1d/vulnsentry)._"
      lines << ""
      lines.join("\n")
    end

    def commit_message_for_bundle(bundle)
      "Bump #{bundle.gem_name} to #{bundle.target_version}"
    end

    def branch_name_for_bundle(bundle)
      base = bundle.base_branch.gsub(/[^A-Za-z0-9._-]/, "-")
      gem = bundle.gem_name.gsub(/[^A-Za-z0-9._-]/, "-")
      ver = bundle.target_version.gsub(/[^A-Za-z0-9._-]/, "-")
      "bump-#{gem}-#{ver}-#{base}"
    end

    def branch_display_name(branch)
      return "master" if branch == "master"
      return "main" if branch == "main"
      return branch.tr("_", ".").sub("ruby.", "Ruby ") if branch.start_with?("ruby_")
      branch.tr("-", " ").titleize
    end

    def fork_git_url
      @project.fork_git_url.presence || "git@github.com:#{@project.fork_repo}.git"
    end

    def fork_owner
      @project.fork_repo.to_s.split("/", 2).first
    end

    def git_env
      env = { "GIT_TERMINAL_PROMPT" => "0" }
      env["GIT_SSH_COMMAND"] = ENV["GIT_SSH_COMMAND"] if ENV["GIT_SSH_COMMAND"].present?
      env
    end

    def remote_branch_exists?(repo_dir, branch_name)
      within_repo(repo_dir) do
        out = run_git!(
          "ls-remote",
          "--heads",
          "fork",
          "refs/heads/#{branch_name}",
          env: git_env
        )
        out.present?
      end
    rescue Error
      false
    end

    def within_repo(repo_dir)
      Dir.chdir(repo_dir) { yield }
    end

    def run_git!(*args, dir: nil, env: nil)
      cmd = [ "git", *args ]
      opts = {}
      opts[:chdir] = dir if dir.present?
      stdout, stderr, status = Open3.capture3(env || {}, *cmd, **opts)
      return stdout if status.success?
      raise Error, "git failed: #{cmd.join(' ')}: #{stderr.strip}"
    end
  end
end
