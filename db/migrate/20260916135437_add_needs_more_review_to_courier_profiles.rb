# A REVIEW THAT ASKS, rather than one that refuses.
#
# Hamma9900's approval flow: an applicant CAN log in but cannot start, and if
# something is missing **we notify them and they send it from the phone.** That
# is not a refusal, and it must never read like one — an applicant who forgot a
# photo and is told he was rejected is a courier we had already convinced and
# then lost.
#
# `verification_status` had pending / approved / rejected / suspended, so
# "we asked you for something" could only be expressed as one of those. Now it
# is its own state, which is what lets the copy differ: "we need one more
# thing" and "we cannot accept you" are different sentences with different
# consequences.
#
# `review_note` rather than reusing `rejection_reason`, because a column named
# for a refusal carrying "your tazkira photo is blurry" is exactly the naming
# drift that misleads whoever reads it next. The `missing` list already covers
# fields that are absent; this is for the things a human notices and a
# validation cannot.
class AddNeedsMoreReviewToCourierProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :courier_profiles, :review_note, :text
    add_column :courier_profiles, :reviewed_at, :datetime
  end
end
