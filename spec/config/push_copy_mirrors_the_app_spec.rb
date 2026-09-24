require "rails_helper"

# ── THE SERVER'S NEW-ORDER WORDS ARE THE APP'S, TEXT FOR TEXT ──────────────
#
# A deliberate duplicate (config/push/merchant_new_order.yml, and
# docs/API_VOCABULARY.md §F): the server writes the one push that must be
# readable with the app closed. "It exists in three languages" would let the
# two copies drift the day someone improves either side's wording, and a
# drifting duplicate is worse than an honest one — nobody can tell which is
# live. So this compares them character for character.
#
# It reads karwan-mobile, so it can only run where both repos sit side by
# side. Where the app is absent it SKIPS AND SAYS SO, rather than passing: a
# green that checked nothing is the one outcome this file must not produce.
RSpec.describe "the server's push copy mirrors the app's" do
  let(:app_locales) { Rails.root.join("../karwan-mobile/src/i18n/locales") }

  def app_copy(locale)
    text = app_locales.join("#{locale}.ts").read
    start = text.index("      new_order: {") or raise "no merchant.alert.new_order block in #{locale}.ts"
    block = text[start...text.index("},", start)]
    %w[title body].to_h { |field| [ field, block[/#{field}:\s*"((?:[^"\\]|\\.)*)"/, 1] ] }
  end

  User::LOCALES.each do |locale|
    it "has the #{locale} title and body exactly as the app words them" do
      skip "karwan-mobile is not checked out beside karwan-api — the mirror cannot be compared here" unless app_locales.exist?

      expect(Notifications::PushCopy.templates.fetch(locale)).to eq(app_copy(locale)),
        "config/push/merchant_new_order.yml (#{locale}) no longer matches karwan-mobile's " \
        "merchant.alert.new_order. Change the words in the app first, then mirror them here."
    end
  end
end
