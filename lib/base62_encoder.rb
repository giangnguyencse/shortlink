# frozen_string_literal: true

# ============================================================
# Base62Encoder — Pure encoding/decoding module
# ============================================================
# Responsibilities:
#   - encode(number)   → Base62 string
#   - decode(string)   → Integer
#   - valid_code?(str) → Boolean
#
# Design:
#   - Zero side effects (no IO, no DB, no cache)
#   - Fully unit-testable in isolation
#   - Used by services, never directly by controllers/models
#
# Alphabet order: 0-9, a-z, A-Z (standard Base62)
# 62^7 = 3,521,614,606,208 unique combinations (~3.5 billion)
module Base62Encoder
  ALPHABET = "mK8q1LgYcR3XzV9vW0jN5bT2fP4hH7sJdF6xCwZkAnBpMeGuQySrotiIlaDEUO".freeze
  BASE      = ALPHABET.length.freeze # 62
  MIN_INPUT = 1
  MAX_INPUT = 62**20 # practical upper bound

  module_function

  # Encodes a positive integer into a Base62 string.
  #
  # @param number [Integer] a positive integer
  # @return [String] Base62 encoded string
  # @raise [ArgumentError] if number is not a positive integer
  #
  # @example
  #   Base62Encoder.encode(1_000_000) #=> "4c92"
  def encode(number)
    raise ArgumentError, "number must be a positive Integer, got: #{number.inspect}" \
      unless number.is_a?(Integer) && number >= MIN_INPUT

    digits = []
    while number > 0
      digits.unshift(ALPHABET[number % BASE])
      number /= BASE
    end

    digits.join
  end

  # Decodes a Base62 string back to a positive integer.
  #
  # @param string [String] Base62 encoded string
  # @return [Integer] decoded integer
  # @raise [ArgumentError] if string contains invalid characters
  #
  # @example
  #   Base62Encoder.decode("4c92") #=> 1_000_000
  def decode(string)
    raise ArgumentError, "Invalid Base62 string: #{string.inspect}" unless valid_code?(string)

    string.chars.reduce(0) do |result, char|
      result * BASE + ALPHABET.index(char)
    end
  end

  # Checks whether a string is a valid Base62 code.
  #
  # @param string [String]
  # @return [Boolean]
  def valid_code?(string)
    string.is_a?(String) &&
      string.length.positive? &&
      string.match?(/\A[0-9a-zA-Z]+\z/)
  end
end
