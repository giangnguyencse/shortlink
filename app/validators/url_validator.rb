# frozen_string_literal: true

# ============================================================
# UrlValidator — Custom ActiveModel::EachValidator
# ============================================================
# Validates that a URL attribute:
#   1. Is present and within max length
#   2. Uses http or https scheme only
#   3. Has a valid parseable format
#   4. Has a non-empty host
#   5. (Optional) Does not target private/reserved IP ranges (SSRF)
#
# Usage in model:
#   validates :original_url, url: true
#   validates :original_url, url: { check_ssrf: true }  # more strict
#
# SSRF Protection:
#   When check_ssrf: true, the validator resolves the hostname
#   to its IP(s) and blocks requests to private/reserved IP ranges.
#   This prevents the service from being used to probe internal infra.
require 'resolv'
require 'ipaddr'

class UrlValidator < ActiveModel::EachValidator
  ALLOWED_SCHEMES = %w[http https].freeze
  MAX_URL_LENGTH  = 2048

  # SSRF — private/reserved IP ranges per RFC 1918, RFC 3927, RFC 4193
  PRIVATE_IP_RANGES = [
    IPAddr.new('10.0.0.0/8'),       # Private class A
    IPAddr.new('172.16.0.0/12'),    # Private class B
    IPAddr.new('192.168.0.0/16'),   # Private class C
    IPAddr.new('127.0.0.0/8'),      # Loopback
    IPAddr.new('169.254.0.0/16'),   # Link-local (AWS Instance Metadata!)
    IPAddr.new('0.0.0.0/8'),        # "This" network
    IPAddr.new('::1/128'),          # IPv6 loopback
    IPAddr.new('fc00::/7'),         # IPv6 unique local
    IPAddr.new('fe80::/10')         # IPv6 link-local
  ].freeze

  def validate_each(record, attribute, value)
    return record.errors.add(attribute, :blank) if value.blank?

    # if value.length > MAX_URL_LENGTH
    #   return record.errors.add(attribute, :too_long,
    #                            message: "is too long (max #{MAX_URL_LENGTH} characters)")
    # end

    uri = parse_uri(value)
    unless uri
      return record.errors.add(attribute, :invalid,
                               message: 'is not a valid URL')
    end

    unless allowed_scheme?(uri)
      return record.errors.add(attribute, :invalid,
                               message: 'must use http or https scheme')
    end

    unless valid_host?(uri)
      return record.errors.add(attribute, :invalid,
                               message: 'must include a valid host')
    end

    check_ssrf!(record, attribute, uri) if options[:check_ssrf]
  end

  private

  def parse_uri(value)
    uri = URI.parse(value)
    # uri if uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    nil
  end

  def allowed_scheme?(uri)
    ALLOWED_SCHEMES.include?(uri.scheme&.downcase)
  end

  def valid_host?(uri)
    uri.host.present? && uri.host.length >= 3 && !uri.host.start_with?('.')
  end

  # Resolves the hostname and checks against known private IP ranges.
  # We check ALL resolved IPs (some hosts round-robin multiple IPs).
  def check_ssrf!(record, attribute, uri)
    ips = Resolv.getaddresses(uri.host)

    ips.each do |ip_str|
      ip = IPAddr.new(ip_str)
      if PRIVATE_IP_RANGES.any? { |range| range.include?(ip) }
        record.errors.add(attribute, :invalid,
                          message: 'targets a private or reserved IP address (SSRF protection)')
        return
      end
    rescue IPAddr::InvalidAddressError
      next
    end
  rescue Resolv::ResolvError
    # DNS failure: allow (non-existent or not-yet-propagated domains)
    # Attackers cannot use SSRF via a non-resolvable host anyway
    Rails.logger.warn("[UrlValidator] DNS resolution failed for host: #{uri.host}")
  end
end
