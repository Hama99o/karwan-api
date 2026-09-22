# A staff account for the ops console at /admin.
#
# Separate from User on purpose — see the migration. Admin accounts are created
# out of band; there is no public registration route and there must not be one.
#
# No Google sign-in: Hamma9900 has been explicit about that, so unlike
# hatiwal-api there is no google_auth controller here.
class AdminUser < ApplicationRecord
  devise :database_authenticatable, :recoverable, :rememberable,
         :trackable, :timeoutable, :lockable, :validatable

  has_many :audit_logs, foreign_key: :admin_user_id, inverse_of: :admin_user, dependent: :nullify

  # RESTRICT, not nullify, and the difference is the point. `status_transitions`
  # is append-only and one-way door 3 — *"a timestamp per state transition...
  # Record the actor too"* — so emptying the actor out of a history to make a
  # staff account deletable is deleting the only answer to "who cancelled that
  # order", and a nulled `admin_user_id` reads as the SYSTEM having done it.
  #
  # Nothing deletes an `AdminUser` today: there is no destroy route and no code
  # path. This is what refuses the first one that tries.
  has_many :status_transitions, foreign_key: :admin_user_id, inverse_of: :admin_user,
                                dependent: :restrict_with_error

  validates :name, presence: true

  def to_s
    name.presence || email
  end
end
