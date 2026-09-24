class Setting
  # SETTINGS ARE READ ONCE PER REQUEST, not once per call.
  #
  # Measured 24 Sept 2026: `Setting.fetch` went to the database on every call,
  # and dispatch alone read about two settings per candidate courier — so the
  # work grew with the couriers actually available, which is backwards.
  #
  # `CurrentAttributes` is reset by Rails around every request and every job,
  # so a cached value cannot outlive the unit of work that read it: a number
  # the owner changes in the console reaches the very next request. Any write
  # to a Setting row clears it too (`Setting`'s after_commit), so the request
  # that changes a setting and then reads it sees the new value.
  class RequestCache < ActiveSupport::CurrentAttributes
    attribute :values

    def self.fetch(key)
      self.values ||= {}
      values.fetch(key) { values[key] = yield }
    end

    def self.clear
      self.values = nil
    end
  end
end
