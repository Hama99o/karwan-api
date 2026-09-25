module Merchants
  # A WALL CLOCK, rendered as one.
  #
  # `opens_at` and `closes_at` are `t.time` columns and `config/application.rb`
  # deliberately removes `:time` from `time_zone_aware_types`, because "we open
  # at 09:00" is a fact about a clock on a wall in Kabul and not an instant that
  # moves when a zone changes. Rendering "HH:MM" keeps that true across the
  # wire: a date attached here would invite the client to zone-convert it, and a
  # shop would be advertised as opening four and a half hours late — which is
  # the exact bug the config comment records.
  class OpeningHourSerializer < ApplicationSerializer
    identifier :id

    fields :day_of_week

    field :opens_at do |hour|
      hour.opens_at&.strftime("%H:%M")
    end

    field :closes_at do |hour|
      hour.closes_at&.strftime("%H:%M")
    end

    # Derived from the two times, never stored, so it cannot disagree with
    # them: 23:00-01:00 closes the next day. Said so no client infers it.
    field :closes_next_day do |hour|
      hour.closes_next_day?
    end
  end
end
