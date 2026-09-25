class ErrorReport
  # FILTERED AT CAPTURE, NOT AT DISPLAY.
  #
  # Karwan's errors carry phone numbers, addresses, landmarks, order contents
  # and money, in exception messages above all: a Postgres error quotes the
  # failing row, and a validation error quotes the value. karwan-api is a
  # PUBLIC repository, so nothing that could be a person's data may reach a
  # row, and therefore a log, a screenshot or a fixture.
  #
  # So the message keeps its SHAPE (enough to recognise the error) and loses
  # every value: quoted text, anything after Postgres' "DETAIL:", emails,
  # phone-like digit runs, coordinates and long numbers. Context keeps only
  # an allowlist of keys that describe WHERE, never WHAT; request params,
  # headers and bodies are never captured at all.
  module Redaction
    MAX_MESSAGE = 500
    REDACTED = "[redacted]".freeze

    CONTEXT_KEYS = %w[controller action path job job_class queue rate_limit source].freeze

    module_function

    def message(raw)
      text = raw.to_s.dup
      text = text.sub(/DETAIL:.*/m, "DETAIL: #{REDACTED}")
      text = text.gsub(/'[^']*'|"[^"]*"|“[^”]*”/, REDACTED)                     # quoted values
      text = text.gsub(/\([^()]*\)=\([^()]*\)/, "(#{REDACTED})=(#{REDACTED})")    # Key (phone)=(+93…)
      text = text.gsub(/[\w.+-]+@[\w-]+(\.[\w-]+)+/, REDACTED)                  # emails
      text = text.gsub(/\+?\d[\d\s\-]{6,}\d/, REDACTED)                         # phone-like runs
      text = text.gsub(/-?\d+\.\d{3,}/, REDACTED)                               # coordinates, precise amounts
      text.truncate(MAX_MESSAGE)
    end

    # Our frames and the gem frames' file names only; never local variables.
    def backtrace(lines)
      Array(lines).first(BACKTRACE_LINES).map { |line| line.to_s.sub(%r{\A#{Regexp.escape(Rails.root.to_s)}/}, "") }
    end

    def context(raw)
      return {} unless raw.respond_to?(:to_h)

      raw.to_h.each_with_object({}) do |(key, value), kept|
        key = key.to_s
        next unless CONTEXT_KEYS.include?(key)
        next unless value.is_a?(String) || value.is_a?(Symbol) || value.is_a?(Numeric)

        kept[key] = message(value.to_s).truncate(200)
      end
    end
  end
end
