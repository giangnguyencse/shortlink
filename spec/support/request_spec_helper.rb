# frozen_string_literal: true

module RequestSpecHelper
  # Parse JSON response body
  def json_body
    JSON.parse(response.body)
  end

  def json_data
    json_body['data']
  end

  def json_errors
    json_body['errors']
  end

  def post_json(path, params: {})
    post path, params: params.to_json, headers: { 'Content-Type' => 'application/json' }
  end
end

RSpec.configure do |config|
  config.include RequestSpecHelper, type: :request
end
