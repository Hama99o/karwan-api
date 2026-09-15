module Search
  # THE PRIMARY CROSS-SCRIPT MECHANISM.
  #
  # Romanisation is probabilistic; this is exact. People search for a small,
  # stable set of DISH names, so a curated list of them — every spelling
  # somebody might type, in both scripts — covers the overwhelming majority of
  # real queries and costs nothing at query time.
  #
  # It is a constant rather than a table for v0 because it changes when the
  # menu vocabulary changes, which is rarely, and a table would need an admin
  # screen nobody asked for. When a merchant's own vocabulary needs entries,
  # that is the moment to move it.
  #
  # Every group is a set of EQUIVALENT spellings. Matching any one of them in a
  # name adds all the others to that row's search text, in both directions —
  # so `kabob` finds کباب and کباب finds `kabab`.
  module TermDictionary
    GROUPS = [
      %w[kabab kebab kabob kebob] + [ "کباب" ],
      %w[qabuli qabili kabuli qabeli] + [ "قابلی", "قابلي", "کابلی" ],
      %w[mantu mantoo manto] + [ "منتو", "مانتو" ],
      %w[ashak aushak] + [ "آشک", "اشک", "آشګ" ],
      %w[bolani bulani boulani] + [ "بولانی", "بولاني", "بولانى" ],
      %w[chapli chapali] + [ "چپلی" ],
      %w[karahi karai korma qorma] + [ "کراهی", "قورمه" ],
      %w[shorwa shorba] + [ "شوروا", "شوربا" ],
      %w[naan nan bread] + [ "نان" ],
      %w[firni ferni] + [ "فرنی", "فرني" ],
      %w[jalebi zoolbia] + [ "جلبی" ],
      %w[doogh dogh douq] + [ "دوغ" ],
      %w[chai chay tea] + [ "چای" ],
      %w[burger] + [ "برگر", "بورگر" ],
      %w[pizza] + [ "پیتزا", "پیزا" ],
      %w[sandwich] + [ "ساندویچ" ],
      %w[rice palaw pulao] + [ "پلو", "برنج" ],
      %w[chicken murgh] + [ "مرغ" ],
      %w[lamb goshi mutton] + [ "گوشت" ],
      %w[fish mahi] + [ "ماهی" ],
      %w[salad] + [ "سالاد" ],
      %w[juice sharbat] + [ "شربت", "آبمیوه" ],
      %w[water aab] + [ "آب" ],
      %w[pharmacy dawakhana medicine] + [ "دواخانه", "دوا" ],
      %w[grocery dukan store] + [ "دکان", "دوکان" ],
      %w[book kitab bookshop] + [ "کتاب" ],
      %w[bakery nanwai] + [ "نانوایی", "نانوايي" ],
      %w[sweets shirini] + [ "شیرینی" ],
      %w[breakfast nashta] + [ "ناشتا" ]
    ].freeze

    # term (downcased) => every equivalent spelling
    INDEX = GROUPS.each_with_object({}) do |group, index|
      group.each { |term| index[term.downcase] = group }
    end.freeze

    # Every alternative spelling for the words appearing in `text`.
    def self.expansions_for(text)
      tokens = text.to_s.downcase.split(/[^\p{Alnum}؀-ۿ]+/).reject(&:blank?)

      tokens.flat_map { |token| INDEX[token] || [] }.uniq
    end
  end
end
