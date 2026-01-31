require "open3"
require "tmpdir"

module Github
  class RubyCorePrCreator
    class Error < StandardError; end

    def initialize(gh: GhCli.new, config: BotConfig.instance)
      @gh = gh
      @config = config
    end

    def create_for_candidate!(candidate, draft: false)
      raise Error, "candidate not approved" unless candidate.state == "approved"
      raise Error, "candidate already has PR" if candidate.pull_request.present?

      base_branch = candidate.base_branch
      branch_name = branch_name_for(candidate)

      Dir.mktmpdir("ruby-core-pr-") do |dir|
        repo_dir = File.join(dir, "repo")
        clone_upstream!(dir, repo_dir, base_branch)
        configure_git_identity!(repo_dir)
        create_branch!(repo_dir, branch_name)

        apply_one_line_bump!(repo_dir, candidate)
        commit!(repo_dir, commit_message_for(candidate))
        branch_name = ensure_unique_head_branch!(repo_dir, branch_name)
        push_to_fork!(repo_dir, branch_name)

        pr = ensure_pr!(branch_name, base_branch, candidate, draft: draft)
        { number: pr.fetch("number"), url: pr.fetch("url"), head_branch: branch_name }
      end
    end

    # Creates a PR for a PatchBundle (new architecture with grouped advisories)
    def create_for_patch_bundle!(bundle, draft: false)
      raise Error, "bundle not approved" unless bundle.state == "approved"
      raise Error, "bundle already has PR" if bundle.pull_request.present?
      raise Error, "bundle has no target version" unless bundle.has_fix?

      # Get project from bundle for multi-project support
      @project = bundle.branch_target&.project
      raise Error, "bundle has no associated project" unless @project
      raise Error, "project cannot create PRs (no fork configured)" unless @project.can_create_prs?

      # Check for existing PRs that might already fix this vulnerability
      existing_fix = check_for_existing_fix_pr(bundle)
      if existing_fix
        raise Error, "existing PR may already fix this: #{existing_fix[:url]} - #{existing_fix[:title]}"
      end

      base_branch = bundle.base_branch
      branch_name = branch_name_for_bundle(bundle)

      Dir.mktmpdir("project-pr-") do |dir|
        repo_dir = File.join(dir, "repo")
        clone_upstream_for_project!(dir, repo_dir, base_branch)
        configure_git_identity!(repo_dir)
        create_branch!(repo_dir, branch_name)

        apply_bundle_bump!(repo_dir, bundle)
        commit_for_bundle!(repo_dir, bundle)
        branch_name = ensure_unique_head_branch_for_project!(repo_dir, branch_name)
        push_to_fork_for_project!(repo_dir, branch_name)

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
          upstream_https_url,
          repo_dir,
          dir: work_dir
        )
        within_repo(repo_dir) { run_git!("remote", "add", "fork", fork_git_url) }
      end

      # Project-aware clone using project's upstream_repo
      def clone_upstream_for_project!(work_dir, repo_dir, base_branch)
        run_git!(
          "clone",
          "--depth",
          "1",
          "--branch",
          base_branch,
          project_upstream_https_url,
          repo_dir,
          dir: work_dir
        )
        within_repo(repo_dir) { run_git!("remote", "add", "fork", project_fork_git_url) }
      end

      def configure_git_identity!(repo_dir)
        within_repo(repo_dir) do
          run_git!("config", "user.name", "dan1d")
          run_git!("config", "user.email", "dan1d@users.noreply.github.com")
        end
      end

      def create_branch!(repo_dir, branch_name)
        within_repo(repo_dir) { run_git!("checkout", "-b", branch_name) }
      end

      def apply_one_line_bump!(repo_dir, candidate)
        path = File.join(repo_dir, "gems", "bundled_gems")
        old_content = File.read(path)

        result =
          begin
            RubyCore::BundledGemsBumper.bump!(
              old_content: old_content,
              gem_name: candidate.gem_name,
              target_version: candidate.target_version
            )
          rescue RubyCore::BundledGemsFile::ParseError => e
            assistant = Ai::BundledGemsBumpAssistant.new
            raise Error, e.message unless assistant.enabled?

            assistant.suggest_bump!(
              old_content: old_content,
              gem_name: candidate.gem_name,
              target_version: candidate.target_version
            )
          end

        expected = candidate.proposed_diff.to_s.strip
        actual = "-#{result.fetch(:old_line).rstrip}\n+#{result.fetch(:new_line).rstrip}"
        unless expected.blank? || expected == actual
          raise Error, "proposed diff mismatch (refuse to proceed)"
        end

        File.write(path, result.fetch(:new_content))

        within_repo(repo_dir) do
          diff = run_git!("diff", "--name-only").strip
          raise Error, "unexpected diff files: #{diff.inspect}" unless diff == "gems/bundled_gems"
        end
      end

      def commit!(repo_dir, message)
        within_repo(repo_dir) do
          run_git!("add", "gems/bundled_gems")
          run_git!("commit", "-m", message)
        end
      end

      # Project-aware commit using project's file_path
      def commit_for_bundle!(repo_dir, bundle)
        file_path = @project&.file_path || "gems/bundled_gems"
        message = commit_message_for_bundle(bundle)
        within_repo(repo_dir) do
          run_git!("add", file_path)
          run_git!("commit", "-m", message)
        end
      end

      def ensure_unique_head_branch!(repo_dir, branch_name)
        return branch_name unless remote_branch_exists?(repo_dir, branch_name)

        # If the branch already exists, check whether there's already a PR for it.
        existing = pr_view(@config.upstream_repo, "#{fork_owner}:#{branch_name}")
        return branch_name if existing

        # Avoid force-push: create a new branch name and use it for a new PR.
        2.upto(10) do |n|
          alt = "#{branch_name}-#{n}"
          next if remote_branch_exists?(repo_dir, alt)

          existing_alt = pr_view(@config.upstream_repo, "#{fork_owner}:#{alt}")
          return alt if existing_alt

          within_repo(repo_dir) { run_git!("branch", "-m", alt) }
          return alt
        end

        raise Error, "unable to find unique branch name"
      end

      # Project-aware version
      def ensure_unique_head_branch_for_project!(repo_dir, branch_name)
        upstream = @project.upstream_repo
        fork_owner_name = project_fork_owner

        return branch_name unless remote_branch_exists?(repo_dir, branch_name)

        existing = pr_view(upstream, "#{fork_owner_name}:#{branch_name}")
        return branch_name if existing

        2.upto(10) do |n|
          alt = "#{branch_name}-#{n}"
          next if remote_branch_exists?(repo_dir, alt)

          existing_alt = pr_view(upstream, "#{fork_owner_name}:#{alt}")
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

      # Project-aware push
      def push_to_fork_for_project!(repo_dir, branch_name)
        push_to_fork!(repo_dir, branch_name)
      end

      def ensure_pr!(branch_name, base_branch, candidate, draft:)
        upstream = @config.upstream_repo
        head = "#{fork_owner}:#{branch_name}"

        existing = pr_view(upstream, head)
        return existing if existing

        title = pr_title_for(candidate)
        body = pr_body_for(candidate)

        args = [ "pr", "create", "--repo", upstream, "--head", head, "--base", base_branch, "--title", title, "--body", body ]
        args << "--draft" if draft

        url = @gh.run!(*args).strip
        pr = @gh.json!("pr", "view", "--repo", upstream, url, "--json", "number,url,state")
        pr.merge("url" => pr.fetch("url"))
      end

      def pr_view(upstream, head)
        # `gh pr view` does not support `--head` in all versions; use `gh pr list` instead.
        prs = @gh.json!("pr", "list", "--repo", upstream, "--head", head, "--json", "number,url,state", "--limit", "1")
        return nil unless prs.is_a?(Array)
        prs.first
      rescue Github::GhCli::CommandError
        nil
      end

      # Check for existing open PRs that might already fix the same vulnerability
      def check_for_existing_fix_pr(bundle)
        upstream = @project.upstream_repo
        gem_name = bundle.gem_name
        target_version = bundle.target_version
        base_branch = bundle.base_branch

        # Search for open PRs that mention the gem name and target version
        search_terms = [
          "bump #{gem_name}",
          "update #{gem_name}",
          "#{gem_name} #{target_version}",
          gem_name
        ]

        search_terms.each do |term|
          prs = search_prs(upstream, term, base_branch)
          next if prs.empty?

          # Check if any PR title/body suggests it fixes the same issue
          prs.each do |pr|
            title = pr["title"].to_s.downcase
            # Match if title contains gem name and either "bump", "update", or the version
            if title.include?(gem_name.downcase)
              if title.include?("bump") || title.include?("update") || title.include?(target_version)
                return { url: pr["url"], title: pr["title"], number: pr["number"] }
              end
            end
          end
        end

        nil
      rescue Github::GhCli::CommandError
        # If search fails, don't block PR creation
        nil
      end

      def search_prs(upstream, query, base_branch)
        @gh.json!(
          "pr", "list",
          "--repo", upstream,
          "--base", base_branch,
          "--state", "open",
          "--search", query,
          "--json", "number,url,title,state",
          "--limit", "5"
        )
      rescue Github::GhCli::CommandError
        []
      end

      def pr_title_for(candidate)
        target = branch_display_name(candidate.base_branch)
        "Bump #{candidate.gem_name} to #{candidate.target_version} for #{target}"
      end

      def pr_body_for(candidate)
        lines = []
        lines << "## Summary"
        lines << "- Security bump for bundled gem `#{candidate.gem_name}`."
        lines << "- Scope: version bump only (`gems/bundled_gems`)."
        lines << ""
        lines << "## References"
        lines << "- CVE: #{candidate.advisory.cve}" if candidate.advisory.cve.present?
        lines << "- Advisory: #{candidate.advisory.advisory_url}" if candidate.advisory.advisory_url.present?
        lines << "- Source: #{candidate.advisory.fingerprint}"
        lines << ""
        lines.join("\n")
      end

      def commit_message_for(candidate)
        "Bump #{candidate.gem_name} to #{candidate.target_version}"
      end

      def branch_name_for(candidate)
        base = candidate.base_branch.gsub(/[^A-Za-z0-9._-]/, "-")
        gem = candidate.gem_name.gsub(/[^A-Za-z0-9._-]/, "-")
        ver = candidate.target_version.gsub(/[^A-Za-z0-9._-]/, "-")
        "bump-#{gem}-#{ver}-#{base}"
      end

      # PatchBundle-specific methods

      def apply_bundle_bump!(repo_dir, bundle)
        # Use project's file_path for multi-project support
        file_path = @project&.file_path || "gems/bundled_gems"
        path = File.join(repo_dir, file_path)
        old_content = File.read(path)

        result = bump_for_project(old_content, bundle)

        expected = bundle.proposed_diff.to_s.strip
        actual = "-#{result.fetch(:old_line).rstrip}\n+#{result.fetch(:new_line).rstrip}"
        unless expected.blank? || expected == actual
          raise Error, "proposed diff mismatch (refuse to proceed)"
        end

        File.write(path, result.fetch(:new_content))

        within_repo(repo_dir) do
          diff = run_git!("diff", "--name-only").strip
          raise Error, "unexpected diff files: #{diff.inspect}" unless diff == file_path
        end
      end

      def bump_for_project(old_content, bundle)
        case @project&.file_type
        when "gemfile_lock"
          ProjectFiles::GemfileLockBumper.bump!(
            old_content: old_content,
            gem_name: bundle.gem_name,
            target_version: bundle.target_version
          )
        else
          # Default to bundled_gems format (Ruby Core)
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
      end

      def ensure_pr_for_bundle!(branch_name, base_branch, bundle, draft:)
        # Use project's upstream_repo for multi-project support
        upstream = @project&.upstream_repo || @config.upstream_repo
        fork_owner_name = @project ? project_fork_owner : fork_owner
        head = "#{fork_owner_name}:#{branch_name}"

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

      def pr_title_for_bundle(bundle)
        target = branch_display_name(bundle.base_branch)
        "Bump #{bundle.gem_name} to #{bundle.target_version} for #{target}"
      end

      def pr_body_for_bundle(bundle)
        file_path = @project&.file_path || "gems/bundled_gems"
        file_type_label = @project&.file_type == "gemfile_lock" ? "dependency" : "bundled gem"

        lines = []
        lines << "## Summary"
        lines << "- Security bump for #{file_type_label} `#{bundle.gem_name}`."
        lines << "- Scope: version bump only (`#{file_path}`)."
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
        return branch.tr("_", ".").sub("ruby.", "Ruby ") if branch.start_with?("ruby_")
        branch
      end

      def upstream_https_url
        # Use SSH for cloning (requires SSH key configured)
        "git@github.com:#{@config.upstream_repo}.git"
      end

      def fork_git_url
        @config.fork_git_url.presence || "git@github.com:#{@config.fork_repo}.git"
      end

      def fork_owner
        @config.fork_repo.split("/", 2).first
      end

      # Project-aware URL helpers
      def project_upstream_https_url
        # Use SSH for cloning (requires SSH key configured)
        "git@github.com:#{@project.upstream_repo}.git"
      end

      def project_fork_git_url
        "git@github.com:#{@project.fork_repo}.git"
      end

      def project_fork_owner
        @project.fork_repo.split("/", 2).first
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
