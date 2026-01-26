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
        @gh.json!("pr", "view", "--repo", upstream, "--head", head, "--json", "number,url,state")
      rescue Github::GhCli::CommandError
        nil
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

      def branch_display_name(branch)
        return "master" if branch == "master"
        return branch.tr("_", ".").sub("ruby.", "Ruby ") if branch.start_with?("ruby_")
        branch
      end

      def upstream_https_url
        "https://github.com/#{@config.upstream_repo}.git"
      end

      def fork_git_url
        @config.fork_git_url.presence || "git@github.com:#{@config.fork_repo}.git"
      end

      def fork_owner
        @config.fork_repo.split("/", 2).first
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
