# A customer's saved pins.
#
# AN ADDRESS IS A PIN, A VOICE NOTE AND A PHONE NUMBER — never a typed street
# address. Afghan addresses are unreliable and people navigate by landmarks, so
# the text note is optional and secondary and there is deliberately no
# street/city/postcode anywhere in this payload.
#
# Orders SNAPSHOT these fields rather than referencing a row, so editing or
# deleting a pin never rewrites where a past order went.
class Api::V1::Customers::AddressesController < Api::V1::BaseController
  before_action :set_address, only: %i[update destroy make_default]

  def index
    addresses = policy_scope(Address).kept.default_first

    render_blue_collection(Customers::AddressSerializer, addresses)
  end

  def create
    address = current_user.addresses.build(address_params)
    authorize address, :create?
    attach_voice_note(address)

    if address.save
      render_blue(Customers::AddressSerializer, address, status: :created)
    else
      render_unprocessable_entity(address)
    end
  end

  def update
    authorize @address, :update?

    attach_voice_note(@address)

    if @address.update(address_params)
      render_blue(Customers::AddressSerializer, @address)
    else
      render_unprocessable_entity(@address)
    end
  end

  # Soft delete — one-way door #6. A hard delete would be a hole in the books
  # for anything that referenced it, and the row is tiny.
  def destroy
    authorize @address, :destroy?

    @address.discard!
    head :no_content
  end

  def make_default
    authorize @address, :update?

    # The model demotes the others in the same save, so there can never be two.
    @address.update!(is_default: true)

    render_blue(Customers::AddressSerializer, @address)
  end

  private

  def set_address
    @address = policy_scope(Address).kept.find(params[:id])
  end

  # TOLERANT OF AN ABSENT `address` KEY — the same trap the courier
  # registration hit. A customer records their landmark note AFTER dropping the
  # pin, so a PATCH carrying nothing but the audio is the normal shape here,
  # and `params.require(:address)` turned it into a 500.
  def address_params
    return ActionController::Parameters.new.permit! if params[:address].blank?

    params.require(:address).permit(
      :label, :latitude, :longitude, :landmark_note, :phone, :voice_note_seconds
    )
  end

  # THE LANDMARK VOICE NOTE — the answer to low literacy, and the reason this
  # app does not ask anyone to type an address.
  #
  # AFGHAN_UX.md §2: the customer RECORDS where they live instead of writing
  # it, and the courier plays it at the door. CLAUDE.md's address problem is
  # the same point from the other side — "do not build street addressing";
  # a pin, a spoken landmark and a phone number.
  #
  # `Address` has declared `has_one_attached :voice_note` since the first
  # migration, alongside a `has_voice_note` boolean and a
  # `voice_note_seconds` integer, and NO ENDPOINT EVER ACCEPTED ONE — so the
  # boolean could only ever be a claim about a file that did not exist. It is
  # now derived from the attachment rather than trusted from the client.
  def attach_voice_note(address)
    return if params[:voice_note].blank?

    # The flag is NOT set here. `Address#sync_voice_note_flag` derives it from
    # the attachment on every save, and two places writing one boolean is how
    # they come to disagree.
    address.voice_note.attach(params[:voice_note])
  end
end
