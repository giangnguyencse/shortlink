# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Base62Encoder do
  describe '.encode' do
    subject(:encoded) { described_class.encode(number) }

    context 'with typical sequence values' do
      let(:number) { 1_000_000 }

      it 'returns a non-empty string' do
        expect(encoded).to be_a(String).and be_present
      end

      it 'returns only alphanumeric characters' do
        expect(encoded).to match(/\A[0-9a-zA-Z]+\z/)
      end

      it 'returns a deterministic result' do
        expect(described_class.encode(number)).to eq(described_class.encode(number))
      end
    end

    context 'with different inputs' do
      it 'produces different codes for different inputs' do
        expect(described_class.encode(1_000_001)).not_to eq(described_class.encode(1_000_002))
      end

      it 'handles large numbers' do
        expect { described_class.encode(62**10) }.not_to raise_error
      end
    end

    context 'with invalid input' do
      it 'raises ArgumentError for zero' do
        expect { described_class.encode(0) }.to raise_error(ArgumentError, /positive/)
      end

      it 'raises ArgumentError for negative numbers' do
        expect { described_class.encode(-1) }.to raise_error(ArgumentError, /positive/)
      end

      it 'raises ArgumentError for nil' do
        expect { described_class.encode(nil) }.to raise_error(ArgumentError)
      end

      it 'raises ArgumentError for a string' do
        expect { described_class.encode('abc') }.to raise_error(ArgumentError)
      end
    end
  end

  describe '.decode' do
    context 'with valid Base62 strings' do
      it 'correctly decodes an encoded number (round-trip)' do
        [1, 100, 1_000_000, 999_999_999].each do |num|
          encoded = described_class.encode(num)
          expect(described_class.decode(encoded)).to eq(num)
        end
      end
    end

    context 'with invalid input' do
      it 'raises ArgumentError for a string with invalid characters' do
        expect { described_class.decode('abc!') }.to raise_error(ArgumentError, /Invalid/)
      end

      it 'raises ArgumentError for empty string' do
        expect { described_class.decode('') }.to raise_error(ArgumentError)
      end

      it 'raises ArgumentError for nil' do
        expect { described_class.decode(nil) }.to raise_error(ArgumentError)
      end
    end
  end

  describe '.valid_code?' do
    it 'returns true for lowercase alphanumeric' do
      expect(described_class.valid_code?('abc123')).to be(true)
    end

    it 'returns true for uppercase alphanumeric' do
      expect(described_class.valid_code?('ABC123')).to be(true)
    end

    it 'returns true for mixed case' do
      expect(described_class.valid_code?('GeAi9K')).to be(true)
    end

    it 'returns false for string with special characters' do
      expect(described_class.valid_code?('abc-123')).to be(false)
      expect(described_class.valid_code?('abc_123')).to be(false)
      expect(described_class.valid_code?('abc!')).to be(false)
    end

    it 'returns false for empty string' do
      expect(described_class.valid_code?('')).to be(false)
    end

    it 'returns false for nil' do
      expect(described_class.valid_code?(nil)).to be(false)
    end
  end
end
