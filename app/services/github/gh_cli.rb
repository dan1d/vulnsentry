require "json"
require "open3"

module Github
  class GhCli
    class CommandError < StandardError
      attr_reader :cmd, :stdout, :stderr, :status

      def initialize(message, cmd:, stdout:, stderr:, status:)
        super(message)
        @cmd = cmd
        @stdout = stdout
        @stderr = stderr
        @status = status
      end
    end

    def initialize(env: ENV)
      @env = env
    end

    def run!(*args)
      stdout, stderr, status, cmd = capture!(*args)
      return stdout if status.success?

      raise CommandError.new("gh command failed", cmd: cmd, stdout: stdout, stderr: stderr, status: status)
    rescue Errno::ENOENT => e
      cmd = [ "gh", *args.map(&:to_s) ]
      raise CommandError.new("gh executable not found: #{e.message}", cmd: cmd, stdout: "", stderr: e.message, status: nil)
    end

    def json!(*args)
      stdout, stderr, status, cmd = capture!(*args)
      unless status.success?
        raise CommandError.new("gh command failed", cmd: cmd, stdout: stdout, stderr: stderr, status: status)
      end

      begin
        JSON.parse(stdout)
      rescue JSON::ParserError => e
        raise CommandError.new("gh returned invalid JSON: #{e.message}", cmd: cmd, stdout: stdout, stderr: stderr, status: status)
      end
    end

    # Fetches paginated API results and returns them as a single array.
    # Uses --jq '.[]' to output one JSON object per line (NDJSON), which is
    # compatible with all gh CLI versions (unlike --slurp which requires 2.47.0+).
    def paginated_json!(endpoint)
      stdout, stderr, status, cmd = capture!("api", "--paginate", "--jq", ".[]", endpoint)
      unless status.success?
        raise CommandError.new("gh command failed", cmd: cmd, stdout: stdout, stderr: stderr, status: status)
      end

      return [] if stdout.strip.empty?

      begin
        stdout.each_line.map { |line| JSON.parse(line) }
      rescue JSON::ParserError => e
        raise CommandError.new("gh returned invalid JSON: #{e.message}", cmd: cmd, stdout: stdout, stderr: stderr, status: status)
      end
    end

    private
      def capture!(*args)
        cmd = [ "gh", *args.map(&:to_s) ]
        stdout, stderr, status = Open3.capture3(@env, *cmd)
        [ stdout, stderr, status, cmd ]
      end
  end
end
