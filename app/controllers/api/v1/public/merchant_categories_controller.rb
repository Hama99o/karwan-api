# The global browse taxonomy — Kabab, Mantu, Pizza, Grocery, Pharmacy.
#
# Seeded and tiny, so it is returned whole rather than paginated: a client that
# has to page through fourteen chips is a client doing needless requests on a
# metered connection.
class Api::V1::Public::MerchantCategoriesController < Api::V1::PublicController
  def index
    categories = MerchantCategory.active.ordered

    render json: {
      merchant_categories: categories.map do |category|
        { id: category.id, slug: category.slug, name: category.name_for(locale) }
      end
    }
  end

  private

  def locale
    current_user&.locale || params[:locale].presence_in(User::LOCALES) || "fa"
  end
end
