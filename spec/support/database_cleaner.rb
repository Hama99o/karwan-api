# Transactions per example are enough for isolation BETWEEN examples, but they
# do nothing about rows that were already in the database when the suite
# started. That is not hypothetical: a `bin/rails runner` in RAILS_ENV=test is
# not transactional, so anything it creates survives, and the next suite run
# collides with it on every sequenced unique column — reported as
# "Phone has already been taken" from inside a factory, which sends you looking
# at the factory instead of at the leftovers.
#
# hatiwal's QA handbook records the same class of problem as "Two sessions, one
# database — fixture state is shared, and it bites".
#
# So: truncate once before the suite, then let transactions do the per-example
# work.
RSpec.configure do |config|
  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
  end
end
