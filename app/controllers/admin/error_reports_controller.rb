# What went wrong, newest first, one row per distinct error with its count.
# Index and show only: an error record an operator can edit is not a record.
module Admin
  class ErrorReportsController < Admin::ApplicationController
    def scoped_resource
      ErrorReport.newest_first
    end
  end
end
