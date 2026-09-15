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

    if address.save
      render_blue(Customers::AddressSerializer, address, status: :created)
    else
      render_unprocessable_entity(address)
    end
  end

  def update
    authorize @address, :update?

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

  def address_params
    params.require(:address).permit(
      :label, :latitude, :longitude, :landmark_note, :phone, :voice_note_seconds
    )
  end
end
