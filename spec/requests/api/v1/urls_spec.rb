# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API::V1::Urls', type: :request do
  # ────────────────────────────────────────────────────────
  # POST /api/v1/encode
  # ────────────────────────────────────────────────────────
  describe 'POST /api/v1/encode' do
    let(:valid_url) { 'https://codesubmit.io/library/react' }

    before do
      seq_result = [{ 'nextval' => 9_999_999 }]
      allow(ActiveRecord::Base.connection).to receive(:execute)
        .with("SELECT nextval('short_url_counter')")
        .and_return(seq_result)
    end

    context 'with a valid URL' do
      before { post_json '/api/v1/encode', params: { url: valid_url } }

      it_behaves_like 'a successful JSON response', expected_status: :created

      it 'returns a short_url starting with http' do
        expect(json_data['short_url']).to start_with('http')
      end

      it 'returns the original_url unchanged' do
        expect(json_data['original_url']).to eq(valid_url)
      end

      it 'returns a valid Base62 short_code' do
        expect(json_data['short_code']).to match(/\A[0-9a-zA-Z]+\z/)
      end

      it 'persists the mapping to the database' do
        expect(ShortUrl.count).to eq(1)
      end
    end

    context 'idempotency: same URL encoded twice' do
      it 'returns the same short_code' do
        post_json '/api/v1/encode', params: { url: valid_url }
        first_code = json_data['short_code']

        post_json '/api/v1/encode', params: { url: valid_url }
        expect(json_data['short_code']).to eq(first_code)
      end

      it 'creates only ONE DB record' do
        post_json '/api/v1/encode', params: { url: valid_url }
        post_json '/api/v1/encode', params: { url: valid_url }
        expect(ShortUrl.count).to eq(1)
      end
    end

    context 'with a blank URL' do
      before { post_json '/api/v1/encode', params: { url: '' } }

      it_behaves_like 'an error JSON response', expected_status: :unprocessable_entity
    end

    context 'with an invalid URL' do
      before { post_json '/api/v1/encode', params: { url: 'not-a-url' } }

      it_behaves_like 'an error JSON response', expected_status: :unprocessable_entity
    end

    context 'with an FTP URL' do
      before { post_json '/api/v1/encode', params: { url: 'ftp://example.com' } }

      it_behaves_like 'an error JSON response', expected_status: :unprocessable_entity
    end

    context 'with a URL over 2048 characters' do
      before { post_json '/api/v1/encode', params: { url: "https://example.com/#{'x' * 2050}" } }

      it_behaves_like 'an error JSON response', expected_status: :unprocessable_entity
    end

    context 'with no URL parameter' do
      before { post_json '/api/v1/encode', params: {} }

      it_behaves_like 'an error JSON response', expected_status: :unprocessable_entity
    end
  end

  # ────────────────────────────────────────────────────────
  # POST /api/v1/decode
  # ────────────────────────────────────────────────────────
  describe 'POST /api/v1/decode' do
    let!(:short_url_record) do
      create(:short_url,
             short_code:   'GeAi9K',
             original_url: 'https://codesubmit.io/library/react')
    end

    context 'with a valid short_code (cache miss — cold start)' do
      before do
        Rails.cache.clear
        post_json '/api/v1/decode', params: { short_url: 'GeAi9K' }
      end

      it_behaves_like 'a successful JSON response'

      it 'returns the original_url' do
        expect(json_data['original_url']).to eq('https://codesubmit.io/library/react')
      end

      it 'returns the short_code' do
        expect(json_data['short_code']).to eq('GeAi9K')
      end
    end

    context 'with a cache hit (warm path)' do
      before do
        Rails.cache.write('shortlink:decode:GeAi9K', 'https://codesubmit.io/library/react')
        post_json '/api/v1/decode', params: { short_url: 'GeAi9K' }
      end

      it_behaves_like 'a successful JSON response'

      it 'returns the cached URL' do
        expect(json_data['original_url']).to eq('https://codesubmit.io/library/react')
      end
    end

    context 'persistence: decode works after restart (Redis cleared)' do
      before do
        Rails.cache.clear
        post_json '/api/v1/decode', params: { short_url: 'GeAi9K' }
      end

      it 'returns 200 OK — DB is source of truth, not Redis' do
        expect(response).to have_http_status(:ok)
      end

      it 'returns the correct original_url from DB' do
        expect(json_data['original_url']).to eq('https://codesubmit.io/library/react')
      end
    end

    context 'with a full short URL (not just code)' do
      before do
        Rails.cache.clear
        post_json '/api/v1/decode', params: { short_url: 'http://localhost:3000/GeAi9K' }
      end

      it 'extracts the code and returns the original URL' do
        expect(response).to have_http_status(:ok)
        expect(json_data['original_url']).to eq('https://codesubmit.io/library/react')
      end
    end

    context 'with a non-existent short code' do
      before { post_json '/api/v1/decode', params: { short_url: 'XXXXX' } }

      it_behaves_like 'an error JSON response', expected_status: :not_found
    end

    context 'with special characters (SQL injection attempt)' do
      before { post_json '/api/v1/decode', params: { short_url: "'; DROP TABLE short_urls; --" } }

      it 'returns unprocessable_entity (not a server error)' do
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'does not affect the database' do
        expect(ShortUrl.count).to eq(1)
      end
    end
  end

  # ────────────────────────────────────────────────────────
  # GET /health
  # ────────────────────────────────────────────────────────
  describe 'GET /health' do
    before { get '/health' }

    it 'returns 200 OK' do
      expect(response).to have_http_status(:ok)
    end

    it 'returns {"status":"ok"}' do
      expect(JSON.parse(response.body)['status']).to eq('ok')
    end
  end

  # ────────────────────────────────────────────────────────
  # Unknown routes
  # ────────────────────────────────────────────────────────
  describe 'GET /unknown-route' do
    before { get '/not-a-real-route' }

    it 'returns 404' do
      expect(response).to have_http_status(:not_found)
    end
  end
end

# ────────────────────────────────────────────────────────
# GET /:short_code — Browser Redirect (bonus feature)
# ────────────────────────────────────────────────────────
RSpec.describe 'Redirects', type: :request do
  let!(:short_url_record) do
    create(:short_url,
           short_code:   'GeAi9K',
           original_url: 'https://codesubmit.io/library/react')
  end

  describe 'GET /:short_code (302 redirect)' do
    context 'with a valid short code' do
      before { get '/GeAi9K' }

      it 'returns 302 Found' do
        expect(response).to have_http_status(:found)
      end

      it 'redirects to the original URL' do
        expect(response.headers['Location']).to eq('https://codesubmit.io/library/react')
      end
    end

    context 'with a non-existent short code' do
      before { get '/XXXXX' }

      it 'returns 404 Not Found' do
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
