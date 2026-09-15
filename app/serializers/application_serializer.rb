# Blueprinter base.
#
# ONE SERIALIZER PER ROLE, never one with conditionals. The same order is three
# different things: the courier sees the pickup address and the cash to collect,
# the customer sees an ETA and a first name, the merchant sees neither. A
# serializer full of `if user.courier?` is how those three views become
# impossible to change independently.
class ApplicationSerializer < Blueprinter::Base
  def self.model_name
    ActiveModel::Name.new(self, nil, name.demodulize.delete_suffix("Serializer"))
  end
end
