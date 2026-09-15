# The audit trail, index and show only.
#
# An editable audit log is not an audit log. Administrate would happily generate
# edit and destroy actions here; the routes deliberately do not.
module Admin
  class AuditLogsController < Admin::ApplicationController
    def scoped_resource
      AuditLog.includes(:admin_user, :actor).newest_first
    end
  end
end
