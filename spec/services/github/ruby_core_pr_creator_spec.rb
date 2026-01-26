require "rails_helper"

RSpec.describe Github::RubyCorePrCreator do
  it "refuses when candidate is not approved" do
    candidate = build_stubbed(:candidate_bump, state: "ready_for_review")
    creator = described_class.new(gh: instance_double(Github::GhCli), config: BotConfig.instance)
    expect { creator.create_for_candidate!(candidate) }.to raise_error(Github::RubyCorePrCreator::Error)
  end

  it "refuses when proposed_diff mismatches the computed bump" do
    candidate = create(
      :candidate_bump,
      state: "approved",
      gem_name: "rexml",
      target_version: "3.3.9",
      proposed_diff: "-rexml 3.3.7 https://example.test\n+rexml 3.3.9 https://example.test\n"
    )

    gh = instance_double(Github::GhCli)
    allow(gh).to receive(:json!).and_return(nil)
    allow(gh).to receive(:run!).and_return("https://github.com/ruby/ruby/pull/1\n")

    creator = described_class.new(gh: gh, config: BotConfig.instance)

    allow(creator).to receive(:run_git!) do |*args, **kwargs|
      cmd = args.join(" ")
      next "gems/bundled_gems\n" if cmd.include?("diff --name-only")
      ""
    end

    allow(creator).to receive(:clone_upstream!) do |_work_dir, repo_dir, _base|
      FileUtils.mkdir_p(File.join(repo_dir, "gems"))
      File.write(File.join(repo_dir, "gems", "bundled_gems"), "rexml 3.3.8 https://example.test\n")
      true
    end

    allow(creator).to receive(:configure_git_identity!)
    allow(creator).to receive(:create_branch!)
    allow(creator).to receive(:commit!)
    allow(creator).to receive(:ensure_unique_head_branch!).and_return("bump-rexml-3.3.9-master")
    allow(creator).to receive(:push_to_fork!)
    allow(creator).to receive(:ensure_pr!).and_return({ "number" => 1, "url" => "https://example.test" })

    expect { creator.create_for_candidate!(candidate) }.to raise_error(Github::RubyCorePrCreator::Error, /proposed diff mismatch/)
  end
end
