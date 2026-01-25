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
      cmd = ["gh", *args.map(&:to_s)]
      stdout, stderr, status = Open3.capture3(@env, *cmd)
      return stdout if status.success?

      raise CommandError.new("gh command failed", cmd: cmd, stdout: stdout, stderr: stderr, status: status)
    rescue Errno::ENOENT => e
      raise CommandError.new(
        "gh executable not found: #{e.message}",
        cmd: cmd,
        stdout: "",
        stderr: e.message,
        status: nil
      )
    end

    def json!(*args)
      JSON.parse(run!(*args))
    end
  end
end

