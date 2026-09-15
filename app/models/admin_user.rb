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

  validates :name, presence: true

  def to_s
    name.presence || email
  end
end
