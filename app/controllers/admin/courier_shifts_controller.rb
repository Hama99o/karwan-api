module Admin
  # Shift history, newest first — the order an operator reads it in when the
  # utilisation figure looks wrong and they want to know who was actually on.
  class CourierShiftsController < Admin::ApplicationController
    def scoped_resource
      super.includes(:courier).newest_first
    end
  end
end
