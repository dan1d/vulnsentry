FactoryBot.define do
  factory :admin_user do
    username { Faker::Alphanumeric.alpha(number: 10).downcase }
    password { "password" }
    password_confirmation { "password" }
  end
end
