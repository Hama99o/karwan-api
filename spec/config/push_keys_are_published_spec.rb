require "rails_helper"

# Every title/body key a push can carry is derived from the SENDERS — the
# notifiers in app/services/notifications — and must be listed in
# docs/API_VOCABULARY.md §F, where the app's string sweep can read it. A key
# the app has no string for is a wordless notification, and until a handler
# exists nothing would ever show that it is.
RSpec.describe "push notification keys are published" do
  let(:sent_keys) do
    Dir[Rails.root.join("app/services/notifications/*.rb")].flat_map do |file|
      File.read(file).gsub(/^\s*#.*$/, "").scan(/"([a-z_]+(?:\.[a-z_]+)+\.(?:title|body))"/).flatten
    end.uniq
  end
  let(:section_f) { Rails.root.join("docs/API_VOCABULARY.md").read[/## F · PUSH NOTIFICATIONS.*/m].to_s }

  it "finds the keys the notifiers send" do
    expect(sent_keys).to include("merchant.alert.new_order.title", "customer.arrival.body")
    expect(sent_keys.size).to be >= 12
  end

  it "lists every one of them in §F" do
    missing = sent_keys.reject { |key| section_f.include?("`#{key}`") }

    expect(missing).to be_empty, "sent by a notifier but not in API_VOCABULARY.md §F: #{missing.join(', ')}"
  end
end
