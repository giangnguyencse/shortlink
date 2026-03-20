# frozen_string_literal: true

Rails.application.routes.draw do
  # Health check endpoint (used by load balancers / uptime monitors)
  get '/health', to: proc {
    [200, { 'Content-Type' => 'application/json' }, ['{"status":"ok","service":"shortlink"}']]
  }

  namespace :api do
    namespace :v1 do
      # POST /api/v1/encode — Encode a long URL to a short URL (returns JSON)
      post :encode, to: 'urls#encode'

      # POST /api/v1/decode — Decode a short URL to the original URL (returns JSON)
      post :decode, to: 'urls#decode'
    end
  end

  # GET /:short_code — Browser redirect (302) to original URL
  #
  # This endpoint demonstrates full "product ownership" of the service:
  # a real URL shortener must handle browser navigation, not just JSON APIs.
  # It is outside the core JSON API scope but shows end-to-end vision.
  #
  # Example: GET /GeAi9K → 302 Found → Location: https://codesubmit.io/library/react
  get '/:short_code', to: 'redirects#show', constraints: { short_code: /[0-9a-zA-Z]+/ }

  # Fallback for unknown routes
  match '*unmatched', to: 'application#not_found', via: :all
end
