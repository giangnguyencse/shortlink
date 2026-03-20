# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_03_20_070656) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "short_urls", force: :cascade do |t|
    t.string "short_code", limit: 20, null: false
    t.string "original_url", limit: 2048, null: false
    t.string "url_digest", limit: 64, null: false
    t.datetime "expires_at"
    t.integer "click_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "idx_short_urls_expires_at", where: "(expires_at IS NOT NULL)"
    t.index ["short_code"], name: "idx_short_urls_short_code", unique: true
    t.index ["url_digest"], name: "idx_short_urls_url_digest", unique: true
  end
end
