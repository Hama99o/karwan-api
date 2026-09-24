module Notifications
  # Words for the ONE push the server writes itself — the shop's new-order
  # alert — from config/push/merchant_new_order.yml, a mirror of the app's own
  # strings (see that file's header for why this duplicate exists and what
  # guards it).
  #
  # The templates keep i18next's `{{name}}` placeholders, filled here, so the
  # server's copy can be compared with the app's character for character.
  module PushCopy
    PATH = Rails.root.join("config/push/merchant_new_order.yml")

    def self.templates
      @templates ||= YAML.safe_load_file(PATH).freeze
    end

    # The recipient's own saved language; a locale we have no copy for falls
    # back to Pashto, the first of User::LOCALES.
    def self.new_order(locale:, values:)
      copy = templates[locale.to_s] || templates.fetch(User::LOCALES.first)
      { title: fill(copy.fetch("title"), values), body: fill(copy.fetch("body"), values) }
    end

    def self.fill(template, values)
      template.gsub(/\{\{\s*(\w+)\s*\}\}/) { values.fetch(Regexp.last_match(1).to_sym, "").to_s }
    end
  end
end
