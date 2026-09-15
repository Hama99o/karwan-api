# A courier: operational state plus the onboarding record.
#
# One pool for both demand types. The same human delivers a meal and carries a
# passenger, with one wallet and one commission — the UI says "rider" in the
# food tab and "driver" in the ride tab. Two tables would mean two balances for
# one person, which is how someone ends up blocked from food work while holding
# credit for rides.
#
# Courier registration is nothing like a customer's. A customer is a phone, an
# OTP and a name, because every extra field is a customer lost. A courier
# advances our merchants' food out of their own pocket and carries our cash,
# so they need identity, a guarantor, documents, and a human approval with a
# name attached. None of it can be collected after the fact.
class CourierProfile < ApplicationRecord
  include AttachableDocuments
  # Foreground tracking only, while a job is active. A fix older than this is
  # not a location, it is a memory — dispatch must not offer work based on where
  # someone was an hour ago.
  STALE_AFTER = 5.minutes

  # The demand types a courier can be offered, in Hamma9900's own framing —
  # "one app, two tabs". Not "food_order", which was wrong twice over: it was
  # food-specific on a platform that also carries books, and it mixed a demand
  # type with a table name while its sibling was a bare noun.
  #
  # These are demand types, not class names, and the mapping is declared BY the
  # job classes (`Order::JOB_KIND` = "delivery", `Trip::JOB_KIND` = "ride") so
  # nobody has to remember it and the two cannot drift. A spec asserts this
  # list equals what the job classes declare.
  #
  # A third — a person-to-person parcel — is already under discussion, and
  # adding it is a constant change and a seed, not a migration. That is the
  # whole reason this is an array rather than a boolean per kind.
  JOB_KINDS = %w[delivery ride].freeze

  enum :vehicle_type, { motorbike: 0, bicycle: 1, car: 2, on_foot: 3 }, prefix: :by
  enum :verification_status, { pending: 0, approved: 1, rejected: 2, suspended: 3 },
       prefix: :verification

  belongs_to :user
  # Two approver columns, because there are two kinds of approver and only one
  # of them is real today. `verified_by` is a `User` (an admin-role account
  # acting through the API, which nothing does yet); `verified_by_admin_user`
  # is the Administrate console operator, which is how every approval actually
  # happens. An AdminUser cannot be assigned to a `User` association, so before
  # this the column could only ever hold nil on the one path that approves
  # anyone — and CLAUDE.md is explicit that a nil approver is not a valid state.
  belongs_to :verified_by, class_name: User.name, optional: true
  belongs_to :verified_by_admin_user, class_name: AdminUser.name, optional: true

  # A tazkira photo and a face. Held because someone carrying cash and food we
  # paid for has to be identifiable, not because anyone enjoys collecting them.
  has_one_attached :id_document
  has_one_attached :selfie
  has_one_attached :vehicle_photo

  # `has_one_attached` validates nothing on its own — not the type, not the
  # size. See AttachableDocuments for why that matters on this VPS.
  validates_attached :id_document, :selfie, :vehicle_photo

  # What a human must see before approving. Checked HERE rather than on
  # submission, because an application is built up over several attempts on a
  # bad connection and refusing the whole form for one missing photo is how an
  # application is abandoned. `approve!` cannot pass without them.
  REQUIRED_FOR_APPROVAL = %i[full_name national_id_number guarantor_name guarantor_phone].freeze
  REQUIRED_DOCUMENTS = %i[id_document selfie].freeze

  validates :full_name, :national_id_number, :guarantor_name, :guarantor_phone,
            presence: true, if: :verification_approved?
  validate :accepts_at_least_one_demand_type, if: :verification_approved?
  validate :accepted_job_kinds_are_known

  scope :available, -> { where(is_available: true) }
  scope :accepting, ->(job_kind) { where("accepted_job_kinds @> ARRAY[?]::varchar[]", job_kind.to_s) }
  # The only couriers dispatch may consider for a demand type: approved, on
  # shift, and willing to take that kind of work. One scope for every kind,
  # including ones that do not exist yet.
  scope :dispatchable_for, ->(job_kind) { verification_approved.available.accepting(job_kind) }

  # What the applicant still owes, as field names the app can translate. Never
  # an English sentence: the courier reads Pashto.
  def missing_for_approval
    missing = REQUIRED_FOR_APPROVAL.select { |field| public_send(field).blank? }
    missing += REQUIRED_DOCUMENTS.reject { |doc| public_send(doc).attached? }
    missing << :accepted_job_kinds if accepted_job_kinds.blank?
    missing
  end

  def ready_for_approval?
    missing_for_approval.empty?
  end

  def location_fresh?
    location_updated_at.present? && location_updated_at > STALE_AFTER.ago
  end

  def coordinates
    return nil unless last_latitude && last_longitude

    [ last_latitude, last_longitude ]
  end

  def record_location!(latitude:, longitude:)
    update!(last_latitude: latitude, last_longitude: longitude, location_updated_at: Time.current)
  end

  # Approval is a human decision and must carry a name. A nil approver on an
  # approved courier is not a valid state — it is how "who let this person in?"
  # becomes unanswerable.
  # Approval is what brings a courier into existence operationally, and it
  # takes THREE things — not one. Getting only the first is a courier who
  # believes they were approved and cannot work:
  #
  #   1. the status, so dispatch will consider them
  #   2. the ROLE, without which `OrderPolicy::CourierScope` resolves to
  #      `none` (they see no jobs), `User#switch_role!` refuses (they cannot
  #      reach the courier tab), and every symptom points at the app rather
  #      than at the missing row
  #   3. a WALLET, without which they cannot be charged commission — so
  #      `Couriers::BaseController` refuses them with `no_wallet`
  #
  # The role and the wallet were both missing from this path. They are here, in
  # ONE transaction, because a courier approved with two of the three is a
  # support call nobody can diagnose from the outside.
  def approve!(by:)
    # Whichever kind of approver this is, it is recorded — and one of them must
    # be present. "Who let this person in?" has to be answerable from the row,
    # not only by scanning an audit log, because a question that needs a log
    # scan is a question nobody asks.
    raise ArgumentError, "an approval must name its approver" if by.nil?

    approver = by.is_a?(AdminUser) ? { verified_by_admin_user: by } : { verified_by: by }

    transaction do
      update!({ verification_status: :approved, verified_at: Time.current,
                rejection_reason: nil }.merge(approver))
      user.user_roles.find_or_create_by!(role: :courier)
      CourierWallet.create!(user: user, balance: 0,
                            credit_line: Setting.fetch("default_credit_line")) if user.courier_wallet.nil?
    end
  end

  def reject!(by:, reason:)
    update!(verification_status: :rejected, verified_at: Time.current, verified_by: by,
            rejection_reason: reason, is_available: false)
  end

  # Can this courier be offered this kind of job at all? A funded wallet is
  # checked separately, per job, because it depends on that job's commission.
  def dispatchable_for?(job_kind)
    return false unless verification_approved? && is_available?

    accepted_job_kinds.include?(job_kind.to_s)
  end

  def accepts?(job_kind)
    accepted_job_kinds.include?(job_kind.to_s)
  end

  private

  # An approved courier who accepts neither kind of work can never be offered
  # anything. That is not a courier, it is a silent dead end in the dispatch
  # loop — and it would look like "no couriers available" rather than a
  # misconfigured account.
  def accepts_at_least_one_demand_type
    return if accepted_job_kinds.present?

    errors.add(:accepted_job_kinds, "an approved courier must accept at least one kind of job")
  end

  # An unknown kind in this array is a typo that silently makes the courier
  # undispatchable — it would read as "no couriers available" rather than as a
  # misconfigured account.
  def accepted_job_kinds_are_known
    unknown = accepted_job_kinds.to_a.map(&:to_s) - JOB_KINDS

    errors.add(:accepted_job_kinds, "unknown job kinds: #{unknown.join(', ')}") if unknown.any?
  end
end
