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

ActiveRecord::Schema[8.1].define(version: 2026_04_18_120700) do
  create_table "agent_runs", force: :cascade do |t|
    t.string "agent_name", null: false
    t.decimal "confidence", precision: 4, scale: 2
    t.datetime "created_at", null: false
    t.string "decision"
    t.text "input_snapshot"
    t.text "output_snapshot"
    t.text "reasoning_summary"
    t.string "status", null: false
    t.integer "ticket_id", null: false
    t.datetime "updated_at", null: false
    t.index ["ticket_id"], name: "index_agent_runs_on_ticket_id"
  end

  create_table "business_records", force: :cascade do |t|
    t.integer "company_id", null: false
    t.datetime "created_at", null: false
    t.string "customer_email"
    t.string "external_id", null: false
    t.json "payload", default: {}, null: false
    t.string "record_type", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "external_id"], name: "index_business_records_on_company_id_and_external_id", unique: true
    t.index ["company_id"], name: "index_business_records_on_company_id"
  end

  create_table "companies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.string "slug", null: false
    t.string "support_email", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_companies_on_slug", unique: true
  end

  create_table "customers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_customers_on_email", unique: true
  end

  create_table "knowledge_articles", force: :cascade do |t|
    t.string "category"
    t.integer "company_id", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.string "slug"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_knowledge_articles_on_company_id"
  end

  create_table "messages", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.string "role", null: false
    t.integer "ticket_id", null: false
    t.datetime "updated_at", null: false
    t.index ["ticket_id"], name: "index_messages_on_ticket_id"
  end

  create_table "tickets", force: :cascade do |t|
    t.string "category"
    t.string "channel", null: false
    t.integer "company_id", null: false
    t.datetime "created_at", null: false
    t.string "current_layer", null: false
    t.integer "customer_id", null: false
    t.text "escalation_reason"
    t.text "handoff_note"
    t.decimal "last_confidence", precision: 4, scale: 2
    t.string "priority"
    t.string "status", null: false
    t.text "summary"
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_tickets_on_company_id"
    t.index ["customer_id"], name: "index_tickets_on_customer_id"
  end

  create_table "tool_calls", force: :cascade do |t|
    t.integer "agent_run_id"
    t.datetime "created_at", null: false
    t.text "input_payload"
    t.text "output_payload"
    t.string "status", null: false
    t.integer "ticket_id", null: false
    t.string "tool_name", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_run_id"], name: "index_tool_calls_on_agent_run_id"
    t.index ["ticket_id"], name: "index_tool_calls_on_ticket_id"
  end

  add_foreign_key "agent_runs", "tickets"
  add_foreign_key "business_records", "companies"
  add_foreign_key "knowledge_articles", "companies"
  add_foreign_key "messages", "tickets"
  add_foreign_key "tickets", "companies"
  add_foreign_key "tickets", "customers"
  add_foreign_key "tool_calls", "agent_runs"
  add_foreign_key "tool_calls", "tickets"
end
