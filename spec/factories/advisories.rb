FactoryBot.define do
  factory :advisory do
    gem_name { Faker::Alphanumeric.alpha(number: 8).downcase }
    cve { "CVE-#{Faker::Number.between(from: 2000, to: 2030)}-#{Faker::Number.number(digits: 4)}" }
    source { "ruby_lang" }
    advisory_url { "https://www.ruby-lang.org/en/news/" }
    affected_requirement { ">= 0" }
    fixed_version { "1.0.1" }
    severity { "high" }
    raw { { "source" => source } }
    fingerprint { "#{source}:#{cve}:#{gem_name}:#{fixed_version}" }
  end
end
