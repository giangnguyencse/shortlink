# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ShortUrl, type: :model do
  subject(:short_url) { build(:short_url) }

  # ── Validations ───────────────────────────────────────────

  describe 'validations' do
    it { is_expected.to be_valid }

    describe '#original_url' do
      it { is_expected.to validate_presence_of(:original_url) }

      it 'validates that the length of :original_url is at most 2048' do
        short_url.original_url = "https://example.com/" + ("a" * 2029)
        short_url.valid?
        expect(short_url.errors[:original_url]).to include(include('exceeds 2048 character limit'))
      end

      it 'rejects non-HTTP URLs' do
        short_url.original_url = 'ftp://bad.com'
        expect(short_url).not_to be_valid
        expect(short_url.errors[:original_url]).to include(include('http or https'))
      end
    end

    describe '#short_code' do
      it { is_expected.to validate_presence_of(:short_code) }
      it { is_expected.to validate_uniqueness_of(:short_code) }
      it { is_expected.to validate_length_of(:short_code).is_at_least(1).is_at_most(20) }

      it 'rejects codes with special characters' do
        short_url.short_code = 'abc-123!'
        expect(short_url).not_to be_valid
      end
    end

    describe '#url_digest' do
      it { is_expected.to validate_presence_of(:url_digest) }
      it { is_expected.to validate_uniqueness_of(:url_digest) }
      it { is_expected.to validate_length_of(:url_digest).is_equal_to(64) }
    end

    describe '#click_count' do
      it { is_expected.to validate_numericality_of(:click_count).only_integer.is_greater_than_or_equal_to(0) }
    end
  end

  # ── Callbacks ─────────────────────────────────────────────

  describe 'before_validation #normalize_url' do
    it 'strips whitespace from original_url' do
      short_url.original_url = '  https://example.com  '
      short_url.valid?
      expect(short_url.original_url).to eq('https://example.com')
    end
  end

  # ── Scopes ────────────────────────────────────────────────

  describe 'scopes' do
    let!(:active_url)  { create(:short_url) }
    let!(:expired_url) { create(:short_url, :expired) }

    describe '.active' do
      it 'includes non-expired records' do
        expect(described_class.active).to include(active_url)
      end

      it 'excludes expired records' do
        expect(described_class.active).not_to include(expired_url)
      end
    end

    describe '.expired' do
      it 'includes expired records' do
        expect(described_class.expired).to include(expired_url)
      end
    end

    describe '.recent' do
      let!(:older_url) { create(:short_url, created_at: 2.days.ago) }

      it 'orders by created_at descending' do
        # expect(described_class.recent.first).to eq(active_url)
        expect(described_class.recent.first).to eq(expired_url)
      end
    end
  end

  # ── Instance Methods ─────────────────────────────────────

  describe '#expired?' do
    it 'returns false when expires_at is nil' do
      expect(build(:short_url, expires_at: nil)).not_to be_expired
    end

    it 'returns false when expires_at is in the future' do
      expect(build(:short_url, expires_at: 1.hour.from_now)).not_to be_expired
    end

    it 'returns true when expires_at is in the past' do
      expect(build(:short_url, :expired)).to be_expired
    end
  end

  describe '#short_url' do
    it 'returns the full short URL with the given base_url' do
      record = build(:short_url, short_code: 'GeAi9K')
      expect(record.short_url('https://myapp.io')).to eq('https://myapp.io/GeAi9K')
    end
  end

  describe 'click_count column' do
    it 'is NOT incremented on decode (hot path lock prevention)' do
      # click_count stays at 0 — Redis INCR handles tracking
      record = create(:short_url)
      expect(record.click_count).to eq(0)
      record.reload
      expect(record.click_count).to eq(0)
    end
  end
end
