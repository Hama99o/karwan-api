require "rails_helper"

# ═══ ONE LETTER, SEVERAL CODEPOINTS ════════════════════════════════════════
#
# Found on 2026-09-18 by checking our romanisation table against Unicode CLDR
# at Hamma9900's suggestion. `Search::Transliteration::LETTERS` had `ک`, `ك`
# and `گ` — the PERSIAN gaf — and no entry at all for `ګ`, U+06AB, the PASHTO
# gaf. `variants` silently drops an Arabic character it does not know, so:
#
#   ننګرهار  (Nangarhar)  ->  "nnrhar"     the g deleted
#   غبرګولی  (Pashto gaf) ->  "ghbroli"    ┐ one word, two places
#   غبرگولی  (Persian gaf)->  "ghbrgoli"   ┘ in the index
#   بولانى   (alef maksura) -> "bolan"     ┐ and this one is OUR OWN
#   بولانی   (farsi yeh)    -> "bolani"    ┘ TermDictionary entry
#
# ── WHY THIS SPEC'S DOMAIN IS THE ALPHABET ───────────────────────────────
#
# Four missing keys is the symptom. The cause is that **the table's domain was
# chosen by whoever typed it** rather than by the alphabet it claims to cover —
# the eighth shape, in a different instrument. Adding four keys fixes today and
# leaves the next forgotten letter exactly as findable as this one was, which
# is to say invisible until a merchant cannot be found.
#
# So the gate below iterates the Pashto and Dari letter set and fails on any
# letter the romaniser cannot read. That is the only version of this fix that
# survives the next letter somebody forgets.
RSpec.describe "Variant letters" do
  # The Pashto alphabet, plus the Persian/Arabic forms that reach us from
  # other keyboards. Written out as DATA so the assertion below has a domain
  # that does not depend on the table it is checking.
  PASHTO_AND_DARI_LETTERS = %w[
    ا آ ب پ ت ټ ث ج ځ چ څ ح خ د ډ ذ ر ړ ز ژ ږ س ش ښ ص ض ط ظ ع غ ف ق
    ک ګ گ ل م ن ڼ و ه ې ی ۍ ئ ۀ ك ي ى ة أ إ ؤ
  ].freeze

  describe "the romanisation table" do
    it "can read every letter of the alphabet it claims to cover" do
      unreadable = PASHTO_AND_DARI_LETTERS.reject do |letter|
        folded = Search::Transliteration.fold(letter)
        Search::Transliteration::LETTERS.key?(folded)
      end

      expect(unreadable).to be_empty,
                            "these letters romanise to nothing and are SILENTLY DROPPED from the " \
                            "search index: #{unreadable.join(' ')} — a merchant whose name carries " \
                            "one cannot be found by typing it"
    end

    it "has a letter set to check against, so the example above is not empty" do
      expect(PASHTO_AND_DARI_LETTERS.size).to be > 40
    end

    # The specific letter that started this, asserted by its consequence rather
    # than by its presence in a hash.
    it "keeps the g in Nangarhar" do
      expect(Search::Transliteration.romanisations("ننګرهار")).to include(a_string_matching(/g/))
    end
  end

  describe "two spellings of one letter" do
    # BOTH circulate: CLDR ships `غبرگولی` for Pashto with the Persian gaf,
    # while correct Pashto orthography writes `غبرګولی`, and Kabul phones carry
    # both keyboards.
    it "romanise identically, so one word lands in one place in the index" do
      pashto = Search::Transliteration.romanisations("غبرګولی")
      persian = Search::Transliteration.romanisations("غبرگولی")

      expect(pashto).not_to be_empty, "nothing romanised — the comparison below would be vacuous"
      expect(pashto).to eq(persian)
    end

    it "fold the four yehs onto one" do
      forms = %w[بولانى بولانی بولاني].map { |w| Search::Transliteration.romanisations(w) }

      expect(forms.first).not_to be_empty
      expect(forms.uniq.size).to eq(1)
    end
  end

  # ── THROUGH THE REAL SEARCH PATH, over HTTP ─────────────────────────────
  #
  # `romanisations` is two layers away from what a customer touches, and the
  # distance mattered: these examples first passed against `Merchant.fuzzy` and
  # still returned nothing through the endpoint, because
  # `public/merchants_controller` called `search` (a LIKE) and never fell back
  # to `fuzzy`. The romanisation fallback had no caller at all.
  #
  # So this drives the browse endpoint a first-time user actually hits.
  describe "a customer typing into the browse screen", type: :request do
    def found(query)
      get "/api/v1/public/merchants", params: { q: query }
      JSON.parse(response.body).fetch("merchants").map { |m| m["name"] }
    end

    let!(:merchant) { create(:merchant, name: "غبرګولی شهر نو", is_open: true) }

    it "finds a Pashto-gaf name when the query uses the PERSIAN gaf" do
      expect(found("غبرگولی")).to include("غبرګولی شهر نو")
    end

    it "finds it when both use the same gaf" do
      expect(found("غبرګولی")).to include("غبرګولی شهر نو")
    end

    # The letter that started this, end to end. Before the fold, `ننګرهار`
    # romanised to "nnrhar" with the g deleted, so this query could not match
    # on any spelling.
    it "finds Nangarhar when the customer types nangarhar" do
      create(:merchant, name: "ننګرهار کباب", is_open: true)

      expect(found("nangarhar")).to include("ننګرهار کباب")
    end

    # ── THE CASE TRIGRAM CANNOT RESCUE, and the reason the fold is applied
    #    to the COLUMN and the QUERY and not only to the romanisation ────────
    #
    # Measured: `word_similarity` between the two spellings alone is 0.45 for
    # `ننګرهار` and **0.0 for `ګل`**. One differing character out of seven is
    # noise; one out of two is the whole word. So on a SHORT name the fold is
    # doing all the work and similarity does none — which is why folding only
    # the romanisation would have left this broken while the long-name examples
    # above went green.
    it "finds a two-letter name whose single gaf is the other one" do
      create(:merchant, name: "ګل", is_open: true)

      expect(found("گل")).to include("ګل")
    end

    # AND THE OTHER DIRECTION, which is what folding the QUERY buys.
    #
    # Storing the folded form beside the original covers a Pashto-gaf NAME
    # typed with a Persian gaf: the column carries both. It does nothing for
    # the reverse — a name already written in the canonical spelling stores one
    # form, so a customer typing the Pashto gaf matches neither, and at two
    # letters similarity is 0.0. Only folding the query closes that side.
    #
    # Removing either half leaves one direction broken, which is the whole of
    # "normalise the column and the query through the same function".
    it "finds a Persian-gaf name when the customer types the PASHTO gaf" do
      create(:merchant, name: "گل", is_open: true)

      expect(found("ګل")).to include("گل")
    end

    # The exact path must not be diluted by near misses — fuzzy is a fallback,
    # not a widening.
    it "prefers an exact match and does not fall back when one exists" do
      exact = create(:merchant, name: "Kabab House", is_open: true)
      create(:merchant, name: "Kabob Palace", is_open: true)

      names = found("Kabab House")

      expect(names).to include(exact.name)
      expect(names).not_to include("Kabob Palace")
    end
  end
end
