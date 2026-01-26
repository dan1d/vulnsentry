require "fileutils"
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
        clone_upstream!(dir, base_branch)
        configure_git_identity!(dir)
        create_branch!(dir, branch_name)

        apply_one_line_bump!(dir, candidate)
        commit!(dir, commit_message_for(candidate))
        push_to_fork!(dir, branch_name)

        pr = ensure_pr!(branch_name, base_branch, candidate, draft: draft)
        { number: pr.fetch("number"), url: pr.fetch("url"), head_branch: branch_name }
      end
    end

    private
      def clone_upstream!(dir, base_branch)
        run_git!("clone", "--depth", "1", "--branch", base_branch, upstream_https_url, dir: dir)
        within_repo(dir) { run_git!("remote", "add", "fork", fork_https_url) }
      end

      def configure_git_identity!(dir)
        within_repo(dir) do
          run_git!("config", "user.name", "dan1d")
          run_git!("config", "user.email", "dan1d@users.noreply.github.com")
        end
      end

      def create_branch!(dir, branch_name)
        within_repo(dir) { run_git!("checkout", "-b", branch_name) }
      end

      def apply_one_line_bump!(dir, candidate)
        path = File.join(dir, "gems", "bundled_gems")
        old_content = File.read(path)

        result = RubyCore::BundledGemsBumper.bump!(
          old_content: old_content,
          gem_name: candidate.gem_name,
          target_version: candidate.target_version
        )

        File.write(path, result.fetch(:new_content))

        within_repo(dir) do
          diff = run_git!("diff", "--name-only").strip
          raise Error, "unexpected diff files: #{diff.inspect}" unless diff == "gems/bundled_gems"
        end
      end

      def commit!(dir, message)
        within_repo(dir) do
          run_git!("add", "gems/bundled_gems")
          run_git!("commit", "-m", message)
        end
      end

      def push_to_fork!(dir, branch_name)
        within_repo(dir) do
          run_git!("push", "fork", "HEAD:refs/heads/#{branch_name}")
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

      def fork_https_url
        # Prefer config if user set HTTPS; if SSH is configured, still keep it
        # (user can provision SSH keys in the runtime image).
        url = @config.fork_git_url
        return url if url.to_s.start_with?("http")
        "https://github.com/#{@config.fork_repo}.git"
      end

      def fork_owner
        @config.fork_repo.split("/", 2).first
      end

      def within_repo(dir)
        Dir.chdir(dir) { yield }
      end

      def run_git!(*args, dir: nil)
        cmd = [ "git", *args ]
        stdout, stderr, status = Open3.capture3(*cmd, chdir: dir)
        return stdout if status.success?
        raise Error, "git failed: #{cmd.join(' ')}: #{stderr.strip}"
      end
  end
end
