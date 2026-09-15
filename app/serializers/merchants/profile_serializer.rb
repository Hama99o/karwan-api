module Merchants
  # The merchant's own record, as they see it. Carries the commission rate —
  # they are entitled to know what we take — and the verification state, so a
  # pending merchant understands why nothing is arriving.
  class ProfileSerializer < ApplicationSerializer
    identifier :id

    fields :name, :phone, :status, :is_open, :prep_time_minutes, :commission_rate,
           :landmark_note, :contact_person_name, :contact_person_phone

    field :kind do |merchant|
      merchant.merchant_kind&.slug
    end

    field :accepting_orders do |merchant|
      merchant.accepting_orders?
    end

    field :verified do |merchant|
      merchant.verified?
    end

    field :location do |merchant|
      { latitude: merchant.latitude, longitude: merchant.longitude }
    end

    # Today, per PRODUCT.md: orders, items sold, cash received from couriers,
    # our commission. No charts.
    field :today do |merchant|
      orders = merchant.orders.where(created_at: Time.zone.now.beginning_of_day..)
      delivered = orders.where(status: :delivered)

      {
        orders: orders.count,
        delivered: delivered.count,
        items_sold: OrderItem.where(order: delivered).sum(:quantity),
        # Grouped by currency, never summed across it.
        received: delivered.group(:currency).sum(:merchant_payout),
        commission: delivered.group(:currency).sum(:commission)
      }
    end
  end
end
