class UserPolicy < ApplicationPolicy
  # A person reads and edits themselves. Nothing here lets one user touch
  # another — admin does that through the console, which is a different
  # surface with its own auth.
  def show?   = own?
  def update? = own?

  private

  def own?
    record.id.present? && record.id == user&.id
  end
end
