# HOW BIG A THING IS, on one ordered scale, defined once.
#
# `catalog_items.size_class`, `orders.required_size_class` and
# `CourierProfile::CARRIES` must never drift apart: a size that exists in one
# and not the others is a delivery nobody can be offered.
#
# The scale is deliberately four coarse steps rather than kilograms or
# centimetres. A merchant on a cheap phone can answer "does it fit on a
# motorbike?"; nobody is going to weigh a bed, and a number nobody enters
# accurately is worse than a category everybody understands.
module SizeClasses
  ALL = { small: 0, medium: 1, large: 2, bulky: 3 }.freeze

  # Smallest first. The integers ARE the ordering, which is why they may never
  # be renumbered — and why a new size in the middle would be a data migration
  # rather than a constant change.
  def self.rank(size_class)
    ALL.fetch(size_class.to_s.to_sym)
  end

  # Does `capacity` cover `required`?
  def self.covers?(capacity, required)
    rank(capacity) >= rank(required)
  end
end
