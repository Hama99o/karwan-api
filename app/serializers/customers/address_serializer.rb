module Customers
  # A pin, a spoken landmark, a phone number.
  class AddressSerializer < ApplicationSerializer
    identifier :id

    fields :label, :landmark_note, :phone, :is_default, :voice_note_seconds

    # DERIVED from the attachment, never echoed from the column.
    #
    # `has_voice_note` is a boolean the client used to be able to set while no
    # endpoint accepted a file at all — so it could only ever be a claim about
    # a recording that did not exist, and a courier would arrive at a door
    # expecting a note the app could not play. It is now the truth about a
    # stored file.
    field :has_voice_note do |address|
      address.voice_note.attached?
    end

    # So the courier's app can actually PLAY it. Only present when there is
    # one; a URL to nothing is the same lie as the boolean was.
    field :voice_note_url do |address|
      next nil unless address.voice_note.attached?

      Rails.application.routes.url_helpers.rails_blob_path(address.voice_note, only_path: true)
    end

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
