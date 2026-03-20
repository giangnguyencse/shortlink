# frozen_string_literal: true

# ============================================================
# ApplicationService — Abstract base class for Service Objects
# ============================================================
# Enforces the Service Object pattern:
#   - Single entry point: `SomeService.call(*args)`
#   - Class-level .call delegates to instance #call
#   - Subclasses override #call, NOT .call
#
# Convention:
#   - Always return a ServiceResult
#   - Never raise exceptions for expected business errors
#   - Use Rails.logger for observability
class ApplicationService
  # Class-level delegator: MyService.call(foo:) → MyService.new(foo:).call
  def self.call(...)
    new(...).call
  end

  def call
    raise NotImplementedError, "#{self.class.name}#call must be implemented"
  end

  private

  def success(value = nil)
    ServiceResult.success(value)
  end

  def failure(errors, error_code: :unprocessable_entity)
    ServiceResult.failure(errors, error_code: error_code)
  end

  def cache_key_for(short_code)
    "shortlink:decode:#{short_code}"
  end
end
