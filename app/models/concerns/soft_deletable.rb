# Soft delete for anything that can appear in order history.
#
# Deliberately NOT a `default_scope`. A default scope leaks into every join,
# every association and every `count`, and the escape hatch (`unscoped`) throws
# away the rest of the query with it — so the first time someone needs a
# discarded row they write `unscoped` and silently lose a policy scope too.
# `kept` is explicit, greppable, and cannot be forgotten invisibly: a read path
# that omits it shows deleted rows, which is a visible bug, rather than a
# read path that omits `unscoped` and hides live ones, which is not.
module SoftDeletable
  extend ActiveSupport::Concern

  included do
    scope :kept,      -> { where(deleted_at: nil) }
    scope :discarded, -> { where.not(deleted_at: nil) }
  end

  def discarded?
    deleted_at.present?
  end

  def kept?
    !discarded?
  end

  def discard!
    return true if discarded?

    transaction do
      update!(deleted_at: Time.current)
      discard_dependents!
      true
    end
  end

  def undiscard!
    update!(deleted_at: nil)
  end

  private

  # Override where discarding a parent must hide its children — a merchant
  # that is gone must not leave an orderable menu behind.
  def discard_dependents!
    nil
  end
end
