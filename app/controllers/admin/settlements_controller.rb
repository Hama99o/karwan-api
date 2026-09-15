module Admin
  class SettlementsController < Admin::ApplicationController
    def scoped_resource
      Settlement.includes(:courier, :counted_by).newest_first
    end
  end
end
