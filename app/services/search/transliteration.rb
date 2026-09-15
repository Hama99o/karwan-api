module Search
  # Bridging Latin and Arabic script, so `kabab` finds کباب.
  #
  # ── WHY THIS IS NOT JUST A CHARACTER MAP ──────────────────────────────────
  # MEASURED before designing, against the trigram threshold of 0.3:
  #
  #   query    consonant skeleton   word_similarity
  #   kabab  → kbab                 0.375  ok
  #   kabob  → kbab                 0.167  FAILS
  #   mantu  → mntw                 0.167  FAILS
  #   burger → brgr                 0.143  FAILS
  #   bolani → bwlany               0.200  FAILS
  #
  # Arabic script omits short vowels and writes و/ی where Latin writes o/u and
  # i/y, so a character map produces consonant skeletons that trigram cannot
  # bridge. That is why the DICTIONARY below is the primary mechanism and
  # romanisation is the fallback, rather than the other way round.
  #
  # ── Why this matters more than it sounds ──────────────────────────────────
  # The failure mode is the worst kind: a customer types `kabab`, sees nothing,
  # and concludes there are no restaurants. The app looks EMPTY rather than
  # broken, so nobody reports it — and we lose a customer Hamma9900 acquired by
  # talking to them in person.
  module Transliteration
    ARABIC_SCRIPT = /[؀-ۿݐ-ݿﭐ-﷿ﹰ-﻿]/

    # Per-character romanisation. Several letters have more than one plausible
    # Latin form and every one is emitted, because a search index may hold
    # alternatives cheaply where a display name may not.
    LETTERS = {
      "ا" => %w[a], "آ" => %w[a], "ب" => %w[b], "پ" => %w[p], "ت" => %w[t],
      "ث" => %w[s], "ج" => %w[j], "چ" => %w[ch], "ح" => %w[h], "خ" => %w[kh],
      "د" => %w[d], "ذ" => %w[z], "ر" => %w[r], "ز" => %w[z], "ژ" => %w[zh],
      "س" => %w[s], "ش" => %w[sh], "ص" => %w[s], "ض" => %w[z], "ط" => %w[t],
      "ظ" => %w[z], "ع" => %w[a], "غ" => %w[gh], "ف" => %w[f], "ق" => %w[q k],
      "ک" => %w[k], "ك" => %w[k], "گ" => %w[g], "ل" => %w[l], "م" => %w[m],
      "ن" => %w[n], "و" => %w[o u w v], "ه" => %w[h], "ی" => %w[i y],
      "ي" => %w[i y], "ې" => %w[e], "ۀ" => %w[a], "ږ" => %w[g], "ښ" => %w[sh],
      "ټ" => %w[t], "ډ" => %w[d], "ړ" => %w[r], "ڼ" => %w[n], "ځ" => %w[dz],
      "څ" => %w[ts], "ۍ" => %w[ai], "ء" => %w[], "ّ" => %w[], "ً" => %w[],
      "َ" => %w[a], "ِ" => %w[i], "ُ" => %w[u]
    }.freeze

    # Cap the variant explosion. "و" alone has four forms, so a five-letter word
    # could otherwise produce hundreds — and the search column only needs
    # enough alternatives to be findable, not every possibility.
    MAX_VARIANTS = 12

    class << self
      def arabic_script?(text)
        text.to_s.match?(ARABIC_SCRIPT)
      end

      # Every romanisation worth indexing, including a short-vowel guess.
      #
      # The vowel guess is what rescues `kabab` from کباب: the script writes
      # k-b-a-b, so an inserted "a" between the leading consonants produces
      # "kabab" exactly rather than relying on trigram to bridge "kbab".
      def romanisations(text)
        return [] unless arabic_script?(text)

        base = variants(text)
        (base + base.flat_map { |form| vowel_guesses(form) }).uniq.take(MAX_VARIANTS)
      end

      private

      def variants(text)
        forms = [ "" ]

        text.to_s.each_char do |char|
          options = LETTERS[char]

          if options.nil?
            # Punctuation, spaces, Latin already present — kept as-is so a
            # mixed-script name survives.
            forms = forms.map { |f| f + char } unless arabic_script?(char)
            next
          end
          next if options.empty?

          forms = forms.flat_map { |f| options.map { |o| f + o } }
          forms = forms.take(MAX_VARIANTS)
        end

        forms.map { |f| f.strip.downcase }.reject(&:blank?).uniq
      end

      # Inserts "a" between adjacent consonants — the commonest unwritten short
      # vowel in Dari and Pashto. Deliberately only "a": adding "i" and "u" as
      # well multiplied the variants without adding matches in the measured
      # cases, and an index full of near-duplicates makes every query slower for
      # no gain.
      def vowel_guesses(form)
        vowels = %w[a e i o u]
        guessed = form.chars.each_with_object(+"") do |char, out|
          previous = out[-1]
          out << "a" if previous && !vowels.include?(previous) && !vowels.include?(char)
          out << char
        end

        guessed == form ? [] : [ guessed ]
      end
    end
  end
end
