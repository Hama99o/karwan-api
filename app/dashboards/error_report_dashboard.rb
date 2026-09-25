require "administrate/base_dashboard"

# Every value here was redacted when it was captured (ErrorReport::Redaction),
# so the page cannot show a customer's phone or address even by accident.
class ErrorReportDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    error_class: Field::String,
    message: Field::Text,
    backtrace: Field::Text,
    source: Field::String,
    severity: Field::String,
    handled: Field::Boolean,
    context: Field::String.with_options(searchable: false),
    occurrences: Field::Number,
    first_seen_at: Field::DateTime,
    last_seen_at: Field::DateTime,
    fingerprint: Field::String
  }.freeze

  COLLECTION_ATTRIBUTES = %i[last_seen_at error_class occurrences severity handled source].freeze
  SHOW_PAGE_ATTRIBUTES = %i[
    error_class message occurrences severity handled source context
    first_seen_at last_seen_at backtrace fingerprint
  ].freeze
  FORM_ATTRIBUTES = [].freeze
  COLLECTION_FILTERS = {}.freeze

  def display_resource(report)
    "#{report.error_class} (x#{report.occurrences})"
  end
end
