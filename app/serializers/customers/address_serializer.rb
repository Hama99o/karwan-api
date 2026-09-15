module Customers
  # A pin, a spoken landmark, a phone number.
  class AddressSerializer < ApplicationSerializer
    identifier :id

    fields :label, :landmark_note, :phone, :is_default, :has_voice_note, :voice_note_seconds

    field :location do |address|
      { latitude: address.latitude, longitude: address.longitude }
    end

    # Whether a courier could actually find this place: the pin plus at least
    # one human description, spoken or written. A bare pin is often not enough
    # in a city navigated by landmark.
    field :navigable do |address|
      address.navigable?
    end
  end
end
