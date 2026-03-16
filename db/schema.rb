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

ActiveRecord::Schema[8.0].define(version: 17) do
  create_table "asin_urls", force: :cascade do |t|
    t.integer "category_id", precision: 38, null: false
    t.string "asin", limit: 20, null: false
    t.string "source", limit: 50
    t.datetime "collected_at"
    t.string "status", limit: 20, default: "pending"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id", "asin"], name: "index_asin_urls_on_category_id_and_asin", unique: true
    t.index ["category_id"], name: "index_asin_urls_on_category_id"
    t.index ["status"], name: "index_asin_urls_on_status"
  end

  create_table "categories", force: :cascade do |t|
    t.string "name", limit: 200, null: false
    t.string "slug", limit: 200, null: false
    t.string "amazon_node_id", limit: 50
    t.string "description", limit: 2000
    t.string "target_audience", limit: 500
    t.string "risk_level", limit: 20, default: "low"
    t.text "example_products"
    t.string "status", limit: 20, default: "tracking"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "margin_rate", precision: 5, scale: 2, default: "50.0"
    t.datetime "last_bsr_collected_at"
    t.datetime "last_movers_collected_at"
    t.datetime "last_trends_collected_at"
    t.datetime "last_social_collected_at"
    t.index ["slug"], name: "index_categories_on_slug", unique: true
    t.index ["status"], name: "index_categories_on_status"
  end

  create_table "category_snapshots", force: :cascade do |t|
    t.integer "category_id", precision: 38, null: false
    t.date "snapshot_date", null: false
    t.integer "avg_bsr", precision: 38
    t.decimal "bsr_7d_change", precision: 5, scale: 2
    t.decimal "bsr_30d_change", precision: 5, scale: 2
    t.integer "new_entries", precision: 38
    t.integer "total_products", precision: 38
    t.decimal "avg_price", precision: 10, scale: 2
    t.decimal "price_in_range_pct", precision: 5, scale: 2
    t.integer "avg_reviews", precision: 38
    t.decimal "avg_rating", precision: 3, scale: 2
    t.decimal "fba_ratio", precision: 3, scale: 2
    t.integer "trends_interest", precision: 38
    t.decimal "trends_cv", precision: 5, scale: 4
    t.string "trends_yoy", limit: 20
    t.integer "reddit_mentions", precision: 38
    t.decimal "reddit_sentiment", precision: 3, scale: 2
    t.string "tiktok_views", limit: 50
    t.text "movers_data"
    t.text "competitor_data"
    t.text "raw_data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id", "snapshot_date"], name: "index_category_snapshots_on_category_id_and_snapshot_date", unique: true
    t.index ["category_id"], name: "index_category_snapshots_on_category_id"
  end

  create_table "competitor_stores", force: :cascade do |t|
    t.string "name", limit: 200, null: false
    t.string "url", limit: 500
    t.string "shopify_domain", limit: 200
    t.boolean "active", default: true
    t.datetime "last_crawled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "dbtools$mcp_log", id: :decimal, default: "0.0", force: :cascade do |t|
    t.string "mcp_client", limit: 200, null: false
    t.string "model", limit: 200
    t.string "end_point_type", limit: 12
    t.string "end_point_name", limit: 100, null: false
    t.text "log_message"
    t.datetime "created_on", null: false
    t.string "created_by", limit: 100, default: "USER", null: false
    t.datetime "updated_on"
    t.string "updated_by", limit: 100, default: "USER"
  end

  create_table "excluded_keywords", force: :cascade do |t|
    t.string "keyword", limit: 200, null: false
    t.string "category_pattern", limit: 100
    t.string "reason", limit: 500
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["keyword"], name: "index_excluded_keywords_on_keyword"
  end

# Could not dump table "products" because of following StandardError
#   Unknown type 'VECTOR' for column 'title_vector'

# Could not dump table "recommendations" because of following StandardError
#   Unknown type 'VECTOR' for column 'insight_vector'

  create_table "scrape_metrics", force: :cascade do |t|
    t.string "collector_name", limit: 50, null: false
    t.integer "category_id", precision: 38
    t.date "run_date", null: false
    t.integer "attempted", precision: 38, default: 0
    t.integer "succeeded", precision: 38, default: 0
    t.integer "failed", precision: 38, default: 0
    t.integer "partial", precision: 38, default: 0
    t.decimal "success_rate", precision: 5, scale: 2
    t.integer "avg_response_ms", precision: 38
    t.string "error_summary", limit: 2000
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "trigger_type", limit: 20, default: "on_demand"
    t.string "triggered_by", limit: 100
    t.index ["category_id", "run_date"], name: "index_scrape_metrics_on_category_id_and_run_date"
    t.index ["category_id"], name: "index_scrape_metrics_on_category_id"
    t.index ["collector_name", "run_date"], name: "index_scrape_metrics_on_collector_name_and_run_date"
  end

  create_table "sourcing_batches", force: :cascade do |t|
    t.integer "category_id", precision: 38, null: false
    t.string "phase", limit: 20, null: false
    t.string "status", limit: 20, default: "pending"
    t.integer "total_count", precision: 38, default: 0
    t.integer "processed_count", precision: 38, default: 0
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id", "phase"], name: "index_sourcing_batches_on_category_id_and_phase"
    t.index ["category_id"], name: "index_sourcing_batches_on_category_id"
  end

