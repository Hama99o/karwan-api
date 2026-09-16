require "rails_helper"

# ASSIGNING AN OWNER IS WHAT MAKES SOMEONE A MERCHANT.
#
# Nothing in the app granted `:merchant_owner`. It existed in two seed scripts
# and nowhere else, so the launch-day sequence was: Hamma9900 sits with a
# restaurant owner, onboards them in the console, sets the owner to their phone
# — and that person signs in and cannot reach the merchant tab.
#
# It is the same bug courier approval had (status set, wallet made, role never
# granted), on the path he uses FIRST, because merchants are admin-onboarded
# while couriers self-apply.
RSpec.describe "merchant ownership grants the role", type: :model do
  let(:person) { create(:user) }

  it "grants the merchant role when the owner is assigned" do
    merchant = create(:merchant, owner: nil)

    expect { merchant.update!(owner: person) }
      .to change { person.reload.role?(:merchant_owner) }.from(false).to(true)
  end

  it "grants it when the merchant is created with an owner already set" do
    create(:merchant, owner: person)

    expect(person.reload.role?(:merchant_owner)).to be true
  end

  # PARTNER → CUSTOMER IS AUTOMATIC. Hamma9900: the client account opens with a
  # partner account "because it's not a big thing". A merchant owner who cannot
  # order food breaks the premise the shared pool rests on.
  it "grants the customer role alongside it" do
    person.user_roles.destroy_all
    merchant = create(:merchant, owner: nil)

    merchant.update!(owner: person)

    expect(person.reload.role?(:customer)).to be true
  end

  it "does not duplicate a role the person already holds" do
    merchant = create(:merchant, owner: person)

    expect { merchant.update!(owner_id: nil); merchant.update!(owner: person) }
      .not_to change { person.reload.user_roles.count }
  end

  it "grants nothing when some other field is saved" do
    merchant = create(:merchant, owner: person)

    expect { merchant.update!(name: "New Name") }
      .not_to change { person.reload.user_roles.count }
  end

  describe "taking the restaurant away again" do
    # A former owner keeping merchant access to a restaurant that is no longer
    # theirs is the reverse of the same bug.
    it "revokes the role from the previous owner" do
      merchant = create(:merchant, owner: person)

      expect { merchant.update!(owner: nil) }
        .to change { person.reload.role?(:merchant_owner) }.from(true).to(false)
    end

    it "revokes it when the restaurant is handed to somebody else" do
      merchant = create(:merchant, owner: person)
      successor = create(:user)

      merchant.update!(owner: successor)

      expect(person.reload.role?(:merchant_owner)).to be false
      expect(successor.reload.role?(:merchant_owner)).to be true
    end

    # ONE PERSON, TWO RESTAURANTS. Reassigning one must not lock them out of
    # the other — and on a launch where Hamma9900 signs shops one at a time,
    # the first person to own two is not a hypothetical.
    it "leaves the role alone when they still own another merchant" do
      first = create(:merchant, owner: person)
      create(:merchant, owner: person)

      first.update!(owner: nil)

      expect(person.reload.role?(:merchant_owner)).to be true
    end

    # A soft-deleted restaurant is not a restaurant they run.
    it "revokes the role when their only other merchant is deleted" do
      first = create(:merchant, owner: person)
      other = create(:merchant, owner: person)
      other.discard!

      first.update!(owner: nil)

      expect(person.reload.role?(:merchant_owner)).to be false
    end

    # The outcome at THIS layer. The guard itself is tested in
    # spec/models/user_spec.rb, because nothing here revokes `customer` — so
    # this example passes with or without it and is no test of the guard.
    it "leaves them able to buy food like anybody else" do
      merchant = create(:merchant, owner: person)

      merchant.update!(owner: nil)

      expect(person.reload.role?(:customer)).to be true
    end
  end

  # CUSTOMER → PARTNER IS NEVER AUTOMATIC. Hamma9900: "when we create client,
  # we can't give access to create account as rider etc."
  describe "the asymmetry" do
    it "does not make a customer a merchant by itself" do
      expect(create(:user, :customer).role?(:merchant_owner)).to be false
    end

    it "refuses a session switch into a role nobody granted" do
      session, = UserSession.issue!(create(:user, :customer))

      expect(session.switch_role!(:merchant_owner)).to be false
    end
  end
end
