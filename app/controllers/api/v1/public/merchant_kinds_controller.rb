# WHAT KIND OF PLACE — restaurant, bakery, store, pharmacy, bookshop.
#
# Public because it is needed on the SHOP APPLICATION form, and an applicant
# holds no merchant role by definition — that is what they are applying for.
# There is nothing sensitive in a taxonomy anybody can see by browsing.
#
# Same shape as `merchant_categories`: seeded, tiny, returned whole rather than
# paginated, and named in the caller's own language because the server holds
# the three names and the device cannot translate a taxonomy it did not write.
class Api::V1::Public::MerchantKindsController < Api::V1::PublicController
  def index
    kinds = MerchantKind.active.ordered

    render json: {
      merchant_kinds: kinds.map do |kind|
        { id: kind.id, slug: kind.slug, name: kind.name_for(locale) }
      end
    }
  end

  private

  def locale
    current_user&.locale || params[:locale].presence_in(User::LOCALES) || "fa"
  end
end
