module Admin
  class TripsController < Admin::ApplicationController
    def scoped_resource
      Trip.includes(:passenger, :courier).order(created_at: :desc)
    end
  end
end
