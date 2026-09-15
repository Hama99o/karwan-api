# Append-only. Every money-touching action and every admin intervention:
# actor, action, before, after, timestamp.
#
# This is non-negotiable because the admin surface can change anything about
# anyone — reassign a rider, cancel an order, credit a wallet, mark an order
# failed. `before`/`after` rather than a diff, because a diff cannot be read
# back without the code that produced it and this table outlives that code.
class AuditLog < ApplicationRecord
  enum :actor_role, Roles::ALL, prefix: :by

  belongs_to :actor, class_name: User.name, optional: true
  belongs_to :target, polymorphic: true, optional: true

  validates :action, presence: true

  scope :newest_first, -> { order(created_at: :desc) }
  scope :for_action, ->(action) { where(action: action) }

  # Logging must never be the reason an action fails — but a swallowed
  # exception must still be visible, so it is reported rather than discarded.
  def self.record!(action:, actor: nil, actor_role: nil, target: nil, before: nil, after: nil, details: nil, ip: nil)
    create!(
      action: action, actor: actor, actor_role: actor_role, target: target,
      before: before, after: after, details: details, ip: ip
    )
  rescue StandardError => e
    Rails.logger.error("[audit] failed to record #{action}: #{e.class}: #{e.message}")
    nil
  end
end
