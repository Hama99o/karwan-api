# Seeds, in two clearly separated halves.
#
#   REFERENCE data — settings, merchant kinds, browse categories. Real
#   configuration the app cannot run without. Loaded in EVERY environment,
#   idempotent, and safe to re-run after a deploy: it refreshes what is ours
#   (descriptions, translations) and never overwrites a value an admin tuned.
#
#   SAMPLE data — users, merchants, catalogs, orders, rides. A world you can
#   actually place an order in. Development and test ONLY, and it refuses to
#   run in production rather than trusting anyone to remember.
#
# Run:
#   bin/rails db:seed              # reference, plus sample outside production
#   bin/rails db:seed:replant      # wipe and reseed (never in production)
#   KARWAN_SEED_SAMPLE=false bin/rails db:seed   # reference only
Rails.application.eager_load!

def seed_section(title)
  print "  #{title}... "
  yield
  puts "done"
end

puts "Seeding reference data (#{Rails.env})"
load Rails.root.join("db/seeds/reference.rb")

sample_wanted = ActiveModel::Type::Boolean.new.cast(ENV.fetch("KARWAN_SEED_SAMPLE", "true"))

if Rails.env.production?
  puts "Skipping sample data: never in production."
elsif !sample_wanted
  puts "Skipping sample data: KARWAN_SEED_SAMPLE is false."
else
  puts "Seeding sample data (#{Rails.env})"
  load Rails.root.join("db/seeds/sample.rb")
end

# Volume, opt-in. See db/seeds/stress.rb for scales and for the honest
# caveat about insert_all skipping validations.
if ActiveModel::Type::Boolean.new.cast(ENV.fetch("KARWAN_SEED_STRESS", "false"))
  if Rails.env.production?
    puts "Skipping stress data: never in production."
  else
    puts "Seeding stress data (scale=#{ENV.fetch('KARWAN_SEED_SCALE', 'small')})"
    load Rails.root.join("db/seeds/stress.rb")
  end
end

puts "Seeding complete."
