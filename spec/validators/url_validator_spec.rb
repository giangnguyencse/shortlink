# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UrlValidator do
  # Use an anonymous model to test the validator in isolation
  let(:model_class) do
    Class.new do
      include ActiveModel::Validations
      attr_accessor :url

      validates :url, url: { check_ssrf: false }

      def self.name
        'TestModel'
      end
    end
  end

  subject(:model) do
    obj = model_class.new
    obj.url = url
    obj.validate
    obj
  end

  context 'with valid URLs' do
    %w[
      https://example.com
      http://example.com
      https://www.google.com/path?q=ruby
      https://sub.domain.example.com/a/b/c?d=e&f=g#anchor
      https://example.com:8080/path
    ].each do |valid_url|
      context "when url is '#{valid_url}'" do
        let(:url) { valid_url }

        it { expect(model.errors[:url]).to be_empty }
      end
    end
  end

  context 'with invalid URLs' do
    context 'when blank' do
      let(:url) { '' }

      it 'adds a blank error' do
        expect(model.errors[:url]).to include('can\'t be blank')
      end
    end

    context 'when using ftp scheme' do
      let(:url) { 'ftp://example.com/file.zip' }

      it 'rejects non-http(s) schemes' do
        expect(model.errors[:url]).to include(include('http or https'))
      end
    end

    context 'when using javascript scheme (XSS attempt)' do
      let(:url) { 'javascript:alert(1)' }

      it 'rejects javascript scheme' do
        expect(model.errors[:url]).not_to be_empty
      end
    end

    context 'when not a URL at all' do
      let(:url) { 'just-a-string' }

      it 'rejects non-URL strings' do
        expect(model.errors[:url]).not_to be_empty
      end
    end
  end

  context 'with SSRF protection enabled' do
    let(:ssrf_model_class) do
      Class.new do
        include ActiveModel::Validations
        attr_accessor :url

        validates :url, url: { check_ssrf: true }

        def self.name
          'SsrfTestModel'
        end
      end
    end

    subject(:ssrf_model) do
      obj = ssrf_model_class.new
      obj.url = url
      obj.validate
      obj
    end

    context 'when targeting localhost' do
      let(:url) { 'http://localhost/admin' }

      before do
        allow(Resolv).to receive(:getaddresses).with('localhost').and_return(['127.0.0.1'])
      end

      it 'blocks SSRF targeting loopback' do
        expect(ssrf_model.errors[:url]).to include(include('private or reserved IP'))
      end
    end

    context 'when targeting AWS metadata IP' do
      let(:url) { 'http://169.254.169.254/latest/meta-data' }

      before do
        allow(Resolv).to receive(:getaddresses).with('169.254.169.254').and_return(['169.254.169.254'])
      end

      it 'blocks SSRF targeting link-local (AWS metadata)' do
        expect(ssrf_model.errors[:url]).to include(include('private or reserved IP'))
      end
    end

    context 'when targeting a public external URL' do
      let(:url) { 'https://google.com' }

      before do
        allow(Resolv).to receive(:getaddresses).with('google.com').and_return(['142.250.80.46'])
      end

      it 'allows public URLs' do
        expect(ssrf_model.errors[:url]).to be_empty
      end
    end
  end
end
