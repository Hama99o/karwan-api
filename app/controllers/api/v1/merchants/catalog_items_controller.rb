# The merchant's catalog, and the sold-out toggle.
#
# THE TOGGLE IS ITS OWN ROUTE, not a field on the update form. PRODUCT.md is
# explicit that it must be reachable in one action from the ORDER BOARD, because
# it is used mid-rush with wet hands — an update form that also happens to
# accept `is_available` would make it a two-screen job.
class Api::V1::Merchants::CatalogItemsController < Api::V1::Merchants::BaseController
  before_action :set_item, only: %i[update destroy sold_out available]

  def index
    # `skip_policy_scope`, with the authorization done on the MERCHANT instead.
    #
    # `verify_policy_scoped` exists to stop an index returning rows nobody
    # checked — but here the collection is not scoped by a policy, it is
    # derived from `current_merchant`, which is itself resolved from ownership
    # and never from a request parameter. Authorising the merchant is the
    # stronger check: there is no `merchant_id` to tamper with.
    skip_policy_scope
    authorize current_merchant, :manage_catalog?

    categories = current_merchant.catalog_categories.kept.ordered
                                 .includes(catalog_items: { options: :values })

    render_blue_collection(Merchants::CatalogSerializer, categories)
  end

  def create
    authorize current_merchant, :manage_catalog?

    category = current_merchant.catalog_categories.kept.find(item_params[:catalog_category_id])
    item = category.catalog_items.build(item_params.except(:catalog_category_id))
    item.merchant = current_merchant

    if item.save
      render_blue(Merchants::CatalogItemSerializer, item, status: :created)
    else
      render_unprocessable_entity(item)
    end
  end

  def update
    authorize current_merchant, :manage_catalog?

    if @item.update(item_params.except(:catalog_category_id))
      render_blue(Merchants::CatalogItemSerializer, @item)
    else
      render_unprocessable_entity(@item)
    end
  end

  # ONE ACTION. Mid-rush, wet hands.
  def sold_out
    toggle(false)
  end

  def available
    toggle(true)
  end

  # Soft delete — one-way door #6. A hard delete would leave a hole in every
  # order that ever contained this item, and order lines snapshot the name and
  # price precisely so history survives.
  def destroy
    authorize current_merchant, :manage_catalog?

    @item.discard!
    head :no_content
  end

  private

  def toggle(available)
    authorize current_merchant, :manage_catalog?

    @item.update!(is_available: available)
    # Logged because a customer complaining "it said it was available" needs an
    # answer, and because sold-out patterns are how a merchant's real capacity
    # becomes visible.
    AuditLog.record!(
      action: available ? "catalog_item.available" : "catalog_item.sold_out",
      actor: current_user, actor_role: :merchant_owner, target: @item,
      after: { is_available: available }
    )

    render_blue(Merchants::CatalogItemSerializer, @item)
  end

  def set_item
    @item = current_merchant.catalog_items.kept.find(params[:id])
  end

  def item_params
    params.require(:catalog_item).permit(
      :catalog_category_id, :name, :description, :price, :prep_time_minutes, :position
    )
  end
end
