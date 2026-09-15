class UserRole < ApplicationRecord
  enum :role, Roles::ALL

  belongs_to :user

  validates :role, presence: true, uniqueness: { scope: :user_id }
end
