# Menu sections, as the merchant groups them. Their own words, their own order.
class Api::V1::Merchants::CatalogCategoriesController < Api::V1::Merchants::BaseController
  before_action :set_category, only: %i[update destroy]

  def create
    authorize current_merchant, :manage_catalog?

    category = current_merchant.catalog_categories.build(category_params)

    if category.save
      render json: { catalog_category: { id: category.id, name: category.name, position: category.position } },
             status: :created
    else
      render_unprocessable_entity(category)
    end
  end

  def update
    authorize current_merchant, :manage_catalog?

    if @category.update(category_params)
      render json: { catalog_category: { id: @category.id, name: @category.name, position: @category.position } }
    else
      render_unprocessable_entity(@category)
    end
  end

  # Discarding a category discards its items too — see
  # CatalogCategory#discard_dependents!. A category that is gone must not leave
  # orderable items behind.
  def destroy
    authorize current_merchant, :manage_catalog?

    @category.discard!
    head :no_content
  end

  private

  def set_category
    @category = current_merchant.catalog_categories.kept.find(params[:id])
  end

  def category_params
    params.require(:catalog_category).permit(:name, :position)
  end
end
