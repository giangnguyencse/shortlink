# frozen_string_literal: true

# ============================================================
# RedirectsController — Browser redirect (optional, bonus feature)
# ============================================================
# GET /:short_code → 302 Found → Location: <original_url>
#
# Kept separate from UrlsController (which handles JSON API) to honor
# the Single Responsibility Principle — one controller, one job.
#
# Uses UrlDecoderService (same business logic) — no duplication.
# Returns 404 JSON if code not found (consistent error format).
class RedirectsController < ApplicationController
  # GET /:short_code
  def show
    result = UrlDecoderService.call(short_url: params[:short_code])

    if result.success?
      redirect_to result.value[:original_url], allow_other_host: true, status: :found
    else
      render_error(result.error_code, result.errors)
    end
  end
end
