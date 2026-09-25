module Merchants
  # The merchant's own record, as they see it. Carries the commission rate —
  # they are entitled to know what we take — and the verification state, so a
  # pending merchant understands why nothing is arriving.
  class ProfileSerializer < ApplicationSerializer
    identifier :id

    fields :name, :phone, :status, :is_open, :prep_time_minutes, :commission_rate,
           :landmark_note, :contact_person_name, :contact_person_phone,
           # Writable since the profile endpoint existed and never served, so
           # a form could not prefill it and a save overwrote it blind.
           :description

    field :kind do |merchant|
      merchant.merchant_kind&.slug
    end

    # ── WHAT THE CUSTOMER SEES, SHOWN TO THE SHOP ────────────────────────────
    #
    # These were on the customer's card and on nothing the shop could read, so
    # a merchant had no way to know which photograph the app was showing —
    # which matters more here than on most platforms. `AFGHAN_UX.md` §1: a
    # large share of users cannot read fluently, so **the photo IS the label**,
    # and a shop with a dark or wrong storefront photo is mislabelled to every
    # customer who opens the app.
    #
    # The SAME variants the customer is served, deliberately: showing the shop
    # a full-size original while customers get a 1000 px card would hide
    # exactly the softness worth noticing.
    field :logo_url do |merchant|
      Attachments::PublicUrl.for(merchant.logo, variant: :thumb)
    end

    field :storefront_photo_url do |merchant|
      if merchant.storefront_photo.attached?
        Attachments::PublicUrl.for(merchant.storefront_photo, variant: :card)
      end
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
