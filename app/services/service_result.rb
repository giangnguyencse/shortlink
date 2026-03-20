# frozen_string_literal: true

# ============================================================
# ServiceResult — Lightweight Result Monad
# ============================================================
# Replaces exception-driven control flow in service objects.
#
# Advantages over raise/rescue:
#   - Explicit contract: caller must handle both success + failure
#   - No hidden control flow (no exception bubbling)
#   - Composable via #and_then
#   - Immutable (frozen after construction)
#
# Pattern:
#   result = SomeService.call(...)
#   result.success?   → true / false
#   result.value      → payload on success
#   result.errors     → array of error messages on failure
#   result.error_code → :not_found, :unprocessable_entity, etc.
class ServiceResult
  attr_reader :value, :errors, :error_code

  # ── Factory Methods ───────────────────────────────────────

  def self.success(value = nil)
    new(success: true, value: value)
  end

  def self.failure(errors, error_code: :unprocessable_entity)
    new(success: false, errors: Array(errors), error_code: error_code)
  end

  # ── Predicates ────────────────────────────────────────────

  def success?
    @success
  end

  def failure?
    !@success
  end

  # ── Functional Composition ───────────────────────────────

  # Chain multiple service calls: short-circuits on first failure.
  #
  # @example
  #   result = ValidateUrl.call(url:)
  #             .and_then { |url| UrlEncoderService.call(original_url: url) }
  def and_then
    return self if failure?

    yield(value)
  end

  def on_success(&block)
    block.call(value) if success?
    self
  end

  def on_failure(&block)
    block.call(errors, error_code) if failure?
    self
  end

  # ── Introspection ─────────────────────────────────────────

  def to_s
    if success?
      "#<ServiceResult success value=#{value.inspect}>"
    else
      "#<ServiceResult failure errors=#{errors.inspect} code=#{error_code}>"
    end
  end

  private

  def initialize(success:, value: nil, errors: [], error_code: nil)
    @success    = success
    @value      = value
    @errors     = errors
    @error_code = error_code
    freeze
  end
end
