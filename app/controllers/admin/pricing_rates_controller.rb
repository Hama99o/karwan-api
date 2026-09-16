# The per-vehicle tariffs.
#
# Nothing custom: the form IS the workflow here, exactly as it is for settings.
# Hamma9900 types a number, the audit hook on the base controller records the
# before and after with his name on it, and the next quote reads it.
#
# `Administrate::BaseDashboard` needs a controller per resource even when it
# adds nothing — the routes point at one, and `spec/requests/admin/` proved
# that by failing the moment the route existed without it.
module Admin
  class PricingRatesController < Admin::ApplicationController
    def scoped_resource
      PricingRate.order(:job_kind, :audience, :position, :vehicle_type)
    end
  end
end
