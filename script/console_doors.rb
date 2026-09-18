Rails.application.eager_load!

OURS = ActiveRecord::Base.descendants.reject { |m|
  m.abstract_class? || m.name.nil? ||
    m.name.start_with?("ActiveStorage::", "ActiveRecord::", "SolidQueue::", "SolidCache::", "SolidCable::", "ActionText::", "ActionMailbox::")
}.uniq(&:name).sort_by(&:name)

routes = Hash.new { |h, k| h[k] = [] }
Rails.application.routes.routes.each do |r|
  c = r.defaults[:controller].to_s
  next unless c.start_with?("admin/")
  routes[c.sub("admin/", "")] << r.defaults[:action].to_s
end

# RESOLVE THROUGH REFLECTION, not by name. `transitions` is a HasMany whose
# class is StatusTransition; matching names missed it and reported a model as
# unreachable when it is on the order page.
on_parent = Hash.new { |h, k| h[k] = [] }
Dir.glob("app/dashboards/*_dashboard.rb").each do |file|
  parent_key = File.basename(file, "_dashboard.rb")
  parent = parent_key.camelize.safe_constantize
  next unless parent.respond_to?(:reflect_on_association)

  src = File.read(file)
  shown = src[/SHOW_PAGE_ATTRIBUTES\s*=\s*%i\[(.*?)\]/m, 1].to_s.split
  src.scan(/^\s*(\w+):\s*Field::(HasMany|HasOne|BelongsTo)/) do |assoc, kind|
    reflection = parent.reflect_on_association(assoc.to_sym)
    klass = (reflection&.klass rescue nil)
    next if klass.nil?

    on_parent[klass.name] << { parent: parent_key, kind: kind, on_show: shown.include?(assoc) }
  end
end

# ── REACHABLE IN A WAY THIS SWEEP CANNOT SEE, OR RIGHTLY ABSENT ───────────
#
# Named with the reason, the same shape as the variant gate's SERVED_WHOLE: the
# domain stays derived, and anything NOT listed here has to be decided rather
# than shrugged at. Without this the sweep reports the same four every run and
# people stop reading it — which is how "24 errors, pre-existing" happened.
ACCOUNTED_FOR = {
  "OtpVerification" => "codes are secrets; a console that displays them is worse than one that does not",
  "UserSession" => "revocable from the user's page and surfaced as `live_session_count` — a COMPUTED field, " \
                   "which an association-based sweep cannot see. The token digest is deliberately never shown.",
  "DeviceToken" => "surfaced as `registered_devices_summary` on the user's page, also computed. The token itself " \
                   "is a push credential and is deliberately never shown.",
  "MerchantCategoryAssignment" => "a join table. Assignment happens on the merchant's own form, which is where an " \
                                  "operator is; a join row is not a thing anybody navigates to."
}.freeze

no_door = []
rows = OURS.map do |m|
  plural = m.name.underscore.pluralize
  verbs = routes[plural].uniq
  parents = on_parent[m.name].select { |p| p[:on_show] }
  reachable = verbs.any? || parents.any?
  no_door << m.name unless reachable
  [ m, verbs, parents, reachable ]
end

unexplained = no_door.reject { |name| ACCOUNTED_FOR.key?(name) }

puts format("%-26s %s", "MODEL WITH NO DOOR", "verdict")
puts "-" * 90
no_door.each do |name|
  reason = ACCOUNTED_FOR[name]
  puts format("  %-26s %s", name, reason ? "accounted for — #{reason[0, 60]}..." : "*** UNEXPLAINED ***")
end
puts
puts "MODELS: #{OURS.size}   NO DOOR: #{no_door.size}   UNEXPLAINED: #{unexplained.size}"
puts
if unexplained.any?
  puts "These can be neither created nor corrected by anybody, and nobody has said why:"
  unexplained.each { |name| puts "  #{name}" }
else
  puts "Every model an operator cannot reach is listed with a reason."
end
puts
puts "── creatable/correctable, for the ones that ARE reachable ──"
rows.select { |_m, _v, _p, ok| ok }.each do |m, verbs, parents, _ok|
  can_create = (verbs & %w[new create]).any?
  can_edit   = (verbs & %w[edit update]).any?
  next if can_create && can_edit

  via = parents.map { |p| "#{p[:parent]} page" }.uniq.join(", ")
  puts format("  %-26s create:%-3s edit:%-3s  %s", m.name, can_create ? "yes" : "NO", can_edit ? "yes" : "NO", via.presence || "own route only")
end
