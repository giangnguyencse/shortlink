# frozen_string_literal: true

FactoryBot.define do
  factory :short_url do
    sequence(:original_url) { |n| "https://example.com/path/#{n}" }
    sequence(:url_digest)   { |n| Digest::SHA256.hexdigest("https://example.com/path/#{n}") }
    sequence(:short_code)   { |n| Base62Encoder.encode(1_000_000 + n) }
    click_count  { 0 }
    expires_at   { nil }

    trait :with_clicks do
      click_count { Faker::Number.between(from: 10, to: 5000) }
    end

    trait :expired do
      expires_at { 1.day.ago }
    end

    trait :expiring_soon do
      expires_at { 1.hour.from_now }
    end
  end
end
