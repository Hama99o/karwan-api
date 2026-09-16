module Dispatch
  # CAN ANYBODY CARRY THIS AT ALL?
  #
  # Two questions that look alike and are not, and only one of them is an
  # honest reason to refuse an order:
  #
  #   `any_vehicle?`   — does anybody ON THE PLATFORM own a vehicle that could
  #                      carry this? A permanent fact. If the answer is no, the
  #                      order can never be delivered, and refusing it at
  #                      placement is the honest thing: "we cannot carry a bed"
  #                      before the customer waits is kinder than a silent
  #                      timeout twenty minutes later.
  #
  #   `any_available?` — is a suitable vehicle ONLINE RIGHT NOW? A five-minute
  #                      fact. Refusing on this would turn a delivery we could
  #                      have had into a customer who leaves, so it is a
  #                      WARNING before they commit and nothing more.
  #
  # Approved couriers only, because a pending applicant with a zarang is not
  # part of the fleet yet — they cannot be dispatched to anything.
  class FleetCapability
    def initialize(size_class)
      @size_class = size_class
    end

    # One query, not one per courier: the capacity map is turned into the list
    # of vehicle types that qualify and the database is asked once.
    def any_vehicle?
      return true if nothing_to_check?

      approved.where(vehicle_type: capable_types).exists?
    end

    def any_available?
      return true if nothing_to_check?

      approved.available.where(vehicle_type: capable_types).exists?
    end

    private

    # Everything carries `small`, so the commonest order in this business —
    # food — asks the database nothing at all.
    def nothing_to_check?
      SizeClasses.rank(@size_class) <= SizeClasses.rank(:small)
    end

    def capable_types
      CourierProfile.vehicle_types_carrying(@size_class)
    end

    def approved
      CourierProfile.verification_approved
    end
  end
end
