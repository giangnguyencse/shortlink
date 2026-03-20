# frozen_string_literal: true

module Api
  module V1
    class UrlsController < ApplicationController
      def encode
        result = UrlEncoderService.call(original_url: encode_params[:url])

        if result.success?
          render_success(result.value, status: :created)
        else
          render_error(result.error_code, result.errors)
        end
      end

      def decode
        result = UrlDecoderService.call(short_url: decode_params[:short_url])

        if result.success?
          render_success(result.value)
        else
          render_error(result.error_code, result.errors)
        end
      end

      private

      def encode_params
        params.permit(:url)
      end

      def decode_params
        params.permit(:short_url)
      end
    end
  end
end
