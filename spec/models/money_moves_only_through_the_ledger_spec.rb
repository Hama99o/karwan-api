require "rails_helper"

# ── ONE-WAY DOOR 4, HELD BY A COMMENT UNTIL NOW ────────────────────────────
#
# `CourierWallet#record_entry!` says of itself: *"Single entry point for every
# balance change, so no code path can move money without leaving a ledger row
# saying who moved it."* It is true today — exactly one line in the codebase
# assigns a balance, and it sits inside that method, after the row is written
# and inside the same transaction and `lock!`.
#
# **Nothing enforced it.** `docs/NOTES.md` records "a comment describing what
# the code SHOULD do was never true" as a recurring shape in this repo; this is
# the same shape one step earlier — a comment that IS true and has no reason to
# stay true. A single `wallet.update!(balance: …)` written in a hurry moves
# money with no ledger row, and `spec/models/every_money_movement_is_attributable_spec.rb`
# would not catch it: that file asserts every ENTRY names a person, which says
# nothing about a movement that produced no entry at all.
#
# `CLAUDE.md` makes a ledger entry per money movement one of the six one-way
# doors. A hole in the books cannot be reconstructed later, which is what makes
# this worth a structural gate rather than a review habit.
RSpec.describe "money moves only through the ledger" do
  MUTATION = /
    (?:update!?\(|update_column!?\(|update_columns\(|increment!?\(|decrement!?\()[^)]*balance
    |
    \bbalance\s*(?:\+|-)?=[^=]
  /x

  def code_lines(globs)
    Dir[*globs.map { |g| Rails.root.join(g) }].flat_map do |file|
      File.readlines(file).each_with_index.map { |line, i| [ "#{file.sub(Rails.root.to_s + '/', '')}:#{i + 1}", line ] }
    end.reject { |_, line| line =~ /\A\s*#/ }
  end

  # The one legitimate assignment, and the only one there should ever be.
  THE_ENTRY_POINT = "app/models/courier_wallet.rb".freeze

  # Setting a BRAND NEW wallet's opening value is not a movement — there is no
  # prior balance and nothing moved. Named by exact path so a second one has to
  # be argued for rather than absorbed.
  ALLOWED_ELSEWHERE = { "db/seeds/sample.rb" => "initialises a new wallet to zero" }.freeze

  it "assigns a balance in exactly one place, inside record_entry!" do
    hits = code_lines(%w[app/**/*.rb lib/**/*.rb db/**/*.rb])
             .select { |_, line| line =~ MUTATION }
             .reject { |loc, _| loc.start_with?(THE_ENTRY_POINT) }
             .reject { |loc, _| ALLOWED_ELSEWHERE.key?(loc.split(":").first) }

    expect(hits.map(&:first)).to be_empty,
                                 "money is moved without a ledger row at: #{hits.map(&:first).join(', ')}. " \
                                 "Every balance change goes through CourierWallet#record_entry!, which writes " \
                                 "the entry and the new balance in one transaction under a lock. A ledger entry " \
                                 "per money movement is one of the six one-way doors in CLAUDE.md — a hole in " \
                                 "the books cannot be reconstructed afterwards."
  end

  # ── THE SPELLINGS A LINE-BY-LINE PATTERN CANNOT SEE ─────────────────────
  #
  # Audited 2026-09-24: the pattern above reads ONE LINE at a time, so it
  # misses a multi-line `update!(\n  balance: …)`, and it knows nothing of
  # `update_all` (which also skips every callback), `assign_attributes`,
  # `write_attribute`, `self[:balance] =`, `upsert`/`insert_all`, or a wallet
  # CREATED with money in it. None exist today; this is the net for the day
  # one is written. It reads each file whole, comments stripped.
  #
  # Creating a wallet at a literal zero is not a movement — nothing moved, and
  # `CourierProfile` does exactly that when a courier is approved.
  WHOLE_FILE_MUTATION = /
    \b(?:update_all|update_columns?|update!?|assign_attributes|write_attribute|upsert(?:_all)?|insert_all!?|
         increment!?|decrement!?|create!?|new)\s*\(
    (?:[^()]|\([^()]*\))*?                       # the arguments, one level of nesting
    (?<!_)\bbalance\b(?!_)
    (?:[^()]|\([^()]*\))*\)
    |
    \[:balance\]\s*=[^=]
  /mx

  it "moves no balance in a spelling the line pattern cannot read" do
    hits = Dir[*%w[app/**/*.rb lib/**/*.rb db/**/*.rb].map { |g| Rails.root.join(g) }].flat_map do |file|
      relative = file.sub("#{Rails.root}/", "")
      next [] if relative == THE_ENTRY_POINT || ALLOWED_ELSEWHERE.key?(relative)

      text = File.read(file).gsub(/^\s*#.*$/, "")
      text.to_enum(:scan, WHOLE_FILE_MUTATION).filter_map do
        match = Regexp.last_match
        call = match[0]
        next if call.match?(/\A(?:create!?|new)\s*\(/) && call.match?(/\bbalance:\s*0\b(?![.\d])/)
        # A log or a payload that merely READS the balance is not a write.
        next if call.match?(/\bbalance:\s*(?:\(?\s*)?(?:wallet|courier_wallet|@wallet)\b/)

        "#{relative}:#{text[0...match.begin(0)].count("\n") + 1}"
      end
    end

    expect(hits).to be_empty,
                    "money may be moved without a ledger row at: #{hits.join(', ')}. " \
                    "Every balance change goes through CourierWallet#record_entry!."
  end

  it "can still see a multi-line and an update_all write, so the example above can fail" do
    samples = [
      "wallet.update!(\n  credit_line: 5,\n  balance: 900\n)",
      "CourierWallet.where(id: 1).update_all(balance: 0)",
      "CourierWallet.create!(user: u, balance: 500)",
      "wallet[:balance] = 10"
    ]

    expect(samples.map { |text| text.match?(WHOLE_FILE_MUTATION) }).to all(be(true))
    expect("CourierWallet.create!(user: u, balance: 0, credit_line: 500)".match?(/\bbalance:\s*0\b(?![.\d])/)).to be(true)
  end

  # Guards the guard. If the pattern ever stopped matching — a rename, a
  # different mutation style — the example above would find nothing and pass
  # while checking nothing, which is the vacuous green this repo keeps meeting.
  it "can still see the legitimate assignment it is excluding" do
    inside = code_lines(%W[#{THE_ENTRY_POINT}]).select { |_, line| line =~ MUTATION }

    expect(inside).not_to be_empty,
                          "the pattern no longer matches the assignment inside record_entry!, so the example " \
                          "above cannot fail. Fix the pattern, not this expectation."
  end

  # The behaviour the structure exists to produce, asserted directly rather than
  # inferred from the structure.
  it "writes an entry and the new balance together, or neither" do
    wallet = create(:user, :courier).courier_wallet
    wallet.update!(balance: 1_000)

    expect { wallet.record_entry!(kind: :commission, amount: -250) }
      .to change { wallet.reload.balance }.from(1_000).to(750)
      .and change { wallet.wallet_entries.count }.by(1)

    expect(wallet.wallet_entries.last.balance_after).to eq(750),
                                                        "the entry must carry the balance it produced, or the " \
                                                        "ledger cannot be replayed against the wallet"
  end
end
