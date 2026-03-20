# frozen_string_literal: true

class ApplicationController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods

  before_action :set_locale
  after_action  :set_security_headers

  # ── Rescue From ───────────────────────────────────────────

  rescue_from ActionController::ParameterMissing do |e|
    render_error(:bad_request, "Missing required parameter: #{e.param}")
  end

  rescue_from ActiveRecord::RecordNotFound do |_e|
    render_error(:not_found, 'Resource not found')
  end

  rescue_from ActiveRecord::RecordInvalid do |e|
    render_error(:unprocessable_entity, e.record.errors.full_messages)
  end

  rescue_from ActionDispatch::Http::Parameters::ParseError do |_e|
    render_error(:bad_request, 'Invalid JSON in request body')
  end

  rescue_from ActionController::UnknownFormat do |_e|
    render_error(:not_acceptable, 'Only JSON format is supported')
  end

  # Catchall for unexpected errors — never leak internal details
  rescue_from StandardError do |e|
    Rails.logger.error("[ApplicationController] Unhandled: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    render_error(:internal_server_error, 'An internal server error occurred')
  end

  # ── 404 Route ─────────────────────────────────────────────

  def not_found
    render_error(:not_found, "Route '#{request.path}' does not exist")
  end

  private

  # ── Response Helpers ─────────────────────────────────────

  def render_success(data, status: :ok, meta: {})
    render json: {
      data: data,
      meta: base_meta.merge(meta)
    }, status: status
  end

  def render_error(status, errors, meta: {})
    render json: {
      errors: Array(errors),
      meta:   base_meta.merge(meta)
    }, status: status
  end

  def base_meta
    { request_id: request.uuid }
  end

  # ── Security Headers ─────────────────────────────────────

  def set_security_headers
    response.set_header('X-Content-Type-Options', 'nosniff')
    response.set_header('X-Frame-Options', 'DENY')
    response.set_header('X-XSS-Protection', '1; mode=block')
    response.set_header('Referrer-Policy', 'strict-origin-when-cross-origin')
  end

  def set_locale
    I18n.locale = :en
  end
end
