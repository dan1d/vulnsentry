# frozen_string_literal: true

FactoryBot.define do
  factory :project do
    name { "Ruby Core" }
    slug { "ruby" }
    upstream_repo { "ruby/ruby" }
    fork_repo { "dan1d/ruby" }
    fork_git_url { "git@github.com:dan1d/ruby.git" }
    file_type { "bundled_gems" }
    file_path { "gems/bundled_gems" }
    branch_discovery { "ruby_lang" }
    enabled { true }
    settings { {} }

    trait :ruby do
      # Default is Ruby
    end

    trait :rails do
      name { "Rails" }
      slug { "rails" }
      upstream_repo { "rails/rails" }
      fork_repo { "vulnsentry-bot/rails" }
      fork_git_url { "git@github.com:vulnsentry-bot/rails.git" }
      file_type { "gemfile_lock" }
      file_path { "Gemfile.lock" }
      branch_discovery { "github_releases" }
    end

    trait :mastodon do
      name { "Mastodon" }
      slug { "mastodon" }
      upstream_repo { "mastodon/mastodon" }
      fork_repo { "vulnsentry-bot/mastodon" }
      fork_git_url { "git@github.com:vulnsentry-bot/mastodon.git" }
      file_type { "gemfile_lock" }
      file_path { "Gemfile.lock" }
      branch_discovery { "github_releases" }
    end

    trait :disabled do
      enabled { false }
    end

    trait :without_fork do
      fork_repo { nil }
      fork_git_url { nil }
    end
  end
end
