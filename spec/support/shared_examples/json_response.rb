# frozen_string_literal: true

RSpec.shared_examples 'a successful JSON response' do |expected_status: :ok|
  it "returns HTTP #{expected_status}" do
    expect(response).to have_http_status(expected_status)
  end

  it 'returns Content-Type application/json' do
    expect(response.content_type).to include('application/json')
  end

  it 'includes a data key' do
    expect(json_body).to have_key('data')
  end

  it 'includes a meta key with request_id' do
    expect(json_body).to have_key('meta')
    expect(json_body['meta']).to have_key('request_id')
  end
end

RSpec.shared_examples 'an error JSON response' do |expected_status:|
  it "returns HTTP #{expected_status}" do
    expect(response).to have_http_status(expected_status)
  end

  it 'returns Content-Type application/json' do
    expect(response.content_type).to include('application/json')
  end

  it 'includes an errors key' do
    expect(json_body).to have_key('errors')
    expect(json_body['errors']).to be_an(Array)
    expect(json_body['errors']).not_to be_empty
  end
end
