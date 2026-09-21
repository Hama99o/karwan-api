require "rails_helper"

# ═══ A DASHBOARD FILTER THAT RAISES IS INVISIBLE UNTIL SOMEBODY CLICKS IT ══
#
# `COLLECTION_FILTERS` lambdas are data. Nothing calls them until an operator
# picks the filter, so one that cannot run looks perfectly healthy in the code,
# in every other spec, and on every page except its own.
#
# ── WHAT THIS FOUND, AND IT WAS NOT MINE ─────────────────────────────────
#
# **Inside a dashboard, the bare constant `Order` resolves to
# `Administrate::Order`** — the gem's own sort-direction class. So
# `PricingRateDashboard`'s `deliveries` filter, written as
# `resources.for_job(Order::JOB_KIND)`, raised
# `uninitialized constant Administrate::Order::JOB_KIND` and answered the
# operator with a **500**. On the Config screen correction 13 says Hamma9900
# retunes prices from weekly, that filter had never worked.
#
# The sibling failure is quieter and worse: a filter whose lambda dies inside a
# `where` renders **200 with zero rows**, which is indistinguishable from a
# filter that matched nothing. Both were measured on the rig.
#
# `Trip` is unaffected only because Administrate happens not to define one.
# That is luck, not design, which is why the fix qualifies both.
RSpec.describe "every console filter runs" do
  let(:dashboards) do
    Dir[Rails.root.join("app/dashboards/*_dashboard.rb")].map { |f| File.basename(f, ".rb").camelize.constantize }
  end

  def filters_for(dashboard)
    return {} unless dashboard.const_defined?(:COLLECTION_FILTERS)

    dashboard.const_get(:COLLECTION_FILTERS)
  end

  it "finds filters to check at all" do
    total = dashboards.sum { |dashboard| filters_for(dashboard).size }

    expect(total).to be >= 8, "the sweep found #{total} filters — the check below would be near-vacuous"
  end

  # CALLED, not read. The whole failure mode is that reading them proves nothing
  # — `Order::JOB_KIND` looks correct on the page and resolves to the wrong
  # constant at call time.
  it "calls every filter without raising" do
    broken = dashboards.flat_map do |dashboard|
      model = dashboard.name.sub(/Dashboard\z/, "").safe_constantize
      next [] unless model.respond_to?(:all)

      filters_for(dashboard).filter_map do |name, filter|
        filter.call(model.all).count
        nil
      rescue StandardError => e
        "#{dashboard.name} filter `#{name}` raises #{e.class}: #{e.message}"
      end
    end

    expect(broken).to be_empty, broken.join("\n")
  end

  # ── THE GATE CAN GO RED, AND ON THE REAL COLLISION ───────────────────────
  #
  # Not a fabricated error — the exact constant resolution that caused it. If
  # Administrate ever stops defining `Order`, this example fails and says so,
  # which is the right moment to revisit the `::` qualifications.
  it "still resolves a bare Order inside a dashboard to Administrate's" do
    expect(defined?(Administrate::Order)).to eq("constant"),
                                             "Administrate no longer defines Order — the `::` qualifications in " \
                                             "the dashboards were written for that collision and should be rechecked"
    expect(Administrate::Order).not_to eq(::Order)
    expect { Administrate::Order::JOB_KIND }.to raise_error(NameError)
  end
end
