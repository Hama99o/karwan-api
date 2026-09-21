require "rails_helper"

# ═══ "REVOKE, NEVER DISPLAY" WAS A COMMENT IN routes.rb ════════════════════
#
# `config/routes.rb`, on the revoke-sessions action: *"A lost phone in a cash
# business: somebody can go on shift as that courier and collect our money.
# Revoke, never display."* A real rule, stated once, enforced by nothing.
#
# Administrate renders a page from a dashboard's attribute lists exactly as it
# WRITES from `FORM_ATTRIBUTES` — generically, from data. So a credential
# reaches a browser page by adding one symbol to an array, which is the same
# blind spot that let a balance be typed into a form and that no source-scanning
# gate can see. `spec/models/no_console_form_writes_a_protected_column_spec.rb`
# closed the write half; this is the read half.
#
# The two are not equally bad and the worse one is less obvious.
# `encrypted_password` on a page is a bcrypt digest — embarrassing, not
# dangerous. **`reset_password_token` is a LIVE CREDENTIAL**: anyone who reads it
# off a screen, a screenshot or a support call can take the account over. So is
# `token_digest`, which is what `UserSession` authenticates against.
#
# ── DERIVED FROM THE SCHEMA, NOT FROM A LIST I TYPED ─────────────────────
#
# The protected-column gate names its columns, because "may an operator edit
# this" is a product judgement. This one does not have to: a credential is
# recognisable from its name, and deriving it means a column added by a future
# migration is covered the day it appears rather than the day somebody
# remembers to list it. The exceptions are named instead, which is the smaller
# and more reviewable list.
RSpec.describe "no console page shows a credential" do
  # What a credential column looks like. `_at` timestamps are excluded by shape
  # rather than by exception — `reset_password_sent_at` is a fact about a
  # request, not the secret itself, and an operator asking "did they ask for a
  # reset?" has a real reason to see it.
  CREDENTIAL = /password|_token\z|token_digest|digest\z|secret|unlock_token/i

  # Columns matching the shape that are NOT secrets, each with the reason.
  let(:not_a_secret) do
    {
      "reset_password_sent_at" => "a timestamp, not the token — answers 'did they ask for a reset?'"
    }
  end

  let(:dashboards) do
    Dir[Rails.root.join("app/dashboards/*_dashboard.rb")].map { |f| File.basename(f, ".rb").camelize.constantize }
  end

  def credential_columns(model)
    model.column_names.grep(CREDENTIAL) - not_a_secret.keys
  end

  def exposed(dashboard)
    %i[COLLECTION_ATTRIBUTES SHOW_PAGE_ATTRIBUTES FORM_ATTRIBUTES].flat_map do |list|
      dashboard.const_defined?(list) ? dashboard.const_get(list).map(&:to_s) : []
    end.uniq
  end

  it "finds the models and the credentials at all" do
    models = dashboards.filter_map { |d| d.name.sub(/Dashboard\z/, "").safe_constantize }
    with_credentials = models.select { |m| m.respond_to?(:column_names) && credential_columns(m).any? }

    expect(with_credentials.map(&:name)).to include("User", "AdminUser"),
                                            "the credential sweep found nothing — the check below is vacuous"
  end

  it "puts no credential on any index, show page or form" do
    offences = dashboards.flat_map do |dashboard|
      model = dashboard.name.sub(/Dashboard\z/, "").safe_constantize
      next [] unless model.respond_to?(:column_names)

      (exposed(dashboard) & credential_columns(model)).map do |column|
        "#{dashboard.name} renders #{model.name}##{column} — routes.rb says revoke, never display"
      end
    end

    expect(offences).to be_empty, offences.join("\n")
  end

  it "excuses only columns that exist and names a reason for each" do
    all_columns = dashboards.filter_map { |d| d.name.sub(/Dashboard\z/, "").safe_constantize }
                            .select { |m| m.respond_to?(:column_names) }.flat_map(&:column_names).uniq

    expect(not_a_secret.keys - all_columns).to be_empty, "an exception names a column that no longer exists"
    expect(not_a_secret.values).to all(be_present)
  end

  # ── THE GATE CAN GO RED ──────────────────────────────────────────────────
  #
  # Run against a list that DOES carry a credential, so this cannot join the
  # checks that pass because they look at nothing.
  it "reports a page that renders a credential, and spares the timestamp" do
    secrets = User.column_names.grep(CREDENTIAL) - [ "reset_password_sent_at" ]

    expect(secrets).to include("encrypted_password", "reset_password_token")
    expect(%w[name phone reset_password_sent_at] & secrets).to be_empty,
                                                              "the pattern is swallowing ordinary columns"
    expect(%w[name reset_password_token] & secrets).to eq(%w[reset_password_token])
  end
end
