# Where an error goes, inside his own system (launch readiness A6, 25 Sept 2026).
#
# One row per DISTINCT error (fingerprint), with a count, so a hundred of the
# same exception is one line that says 100 and the one-off stays visible.
# The message is REDACTED BEFORE IT IS WRITTEN (ErrorReport::Redaction):
# karwan-api is a public repository, and a captured row must never be able to
# carry a phone number, an address or an order into a fixture.
class CreateErrorReports < ActiveRecord::Migration[8.1]
  def change
    create_table :error_reports do |t|
      t.string :fingerprint, null: false
      t.string :error_class, null: false
      t.text :message, null: false, default: ""
      t.text :backtrace, null: false, default: ""
      t.string :source
      t.string :severity, null: false
      t.boolean :handled, null: false, default: false
      t.jsonb :context, null: false, default: {}
      t.integer :occurrences, null: false, default: 1
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
    end
    add_index :error_reports, :fingerprint, unique: true
    add_index :error_reports, :last_seen_at
  end
end
