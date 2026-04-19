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

ActiveRecord::Schema[8.1].define(version: 2026_04_20_120008) do
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

  create_table "knowledge_chunks", force: :cascade do |t|
    t.integer "company_id", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.integer "manual_knowledge_entry_id"
    t.integer "position", default: 0, null: false
    t.integer "public_knowledge_source_id"
    t.integer "token_estimate", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_knowledge_chunks_on_company_id"
    t.index ["manual_knowledge_entry_id"], name: "index_knowledge_chunks_on_manual_knowledge_entry_id"
    t.index ["public_knowledge_source_id"], name: "index_knowledge_chunks_on_public_knowledge_source_id"
  end

  create_table "manual_knowledge_entries", force: :cascade do |t|
    t.integer "company_id", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.string "status", default: "active", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_manual_knowledge_entries_on_company_id"
  end

  create_table "messages", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.string "role", null: false
    t.integer "ticket_id", null: false
    t.datetime "updated_at", null: false
    t.index ["ticket_id"], name: "index_messages_on_ticket_id"
  end

  create_table "motor_alert_locks", force: :cascade do |t|
    t.integer "alert_id", null: false
    t.datetime "created_at", null: false
    t.string "lock_timestamp", null: false
    t.datetime "updated_at", null: false
    t.index ["alert_id", "lock_timestamp"], name: "index_motor_alert_locks_on_alert_id_and_lock_timestamp", unique: true
    t.index ["alert_id"], name: "index_motor_alert_locks_on_alert_id"
  end

  create_table "motor_alerts", force: :cascade do |t|
    t.bigint "author_id"
    t.string "author_type"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.boolean "is_enabled", default: true, null: false
    t.string "name", null: false
    t.text "preferences", null: false
    t.integer "query_id", null: false
    t.text "to_emails", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "motor_alerts_name_unique_index", unique: true, where: "deleted_at IS NULL"
    t.index ["query_id"], name: "index_motor_alerts_on_query_id"
    t.index ["updated_at"], name: "index_motor_alerts_on_updated_at"
  end

  create_table "motor_api_configs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "credentials", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.string "name", null: false
    t.text "preferences", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["name"], name: "motor_api_configs_name_unique_index", unique: true, where: "deleted_at IS NULL"
  end

  create_table "motor_audits", force: :cascade do |t|
    t.string "action"
    t.string "associated_id"
    t.string "associated_type"
    t.string "auditable_id"
    t.string "auditable_type"
    t.text "audited_changes"
    t.text "comment"
    t.datetime "created_at"
    t.string "remote_address"
    t.string "request_uuid"
    t.bigint "user_id"
    t.string "user_type"
    t.string "username"
    t.bigint "version", default: 0
    t.index ["associated_type", "associated_id"], name: "motor_auditable_associated_index"
    t.index ["auditable_type", "auditable_id", "version"], name: "motor_auditable_index"
    t.index ["created_at"], name: "index_motor_audits_on_created_at"
    t.index ["request_uuid"], name: "index_motor_audits_on_request_uuid"
    t.index ["user_id", "user_type"], name: "motor_auditable_user_index"
  end

  create_table "motor_configs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value", null: false
    t.index ["key"], name: "index_motor_configs_on_key", unique: true
    t.index ["updated_at"], name: "index_motor_configs_on_updated_at"
  end

  create_table "motor_dashboards", force: :cascade do |t|
    t.bigint "author_id"
    t.string "author_type"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.text "preferences", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["title"], name: "motor_dashboards_title_unique_index", unique: true, where: "deleted_at IS NULL"
    t.index ["updated_at"], name: "index_motor_dashboards_on_updated_at"
  end

  create_table "motor_forms", force: :cascade do |t|
    t.string "api_config_name", null: false
    t.text "api_path", null: false
    t.bigint "author_id"
    t.string "author_type"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.string "http_method", null: false
    t.string "name", null: false
    t.text "preferences", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "motor_forms_name_unique_index", unique: true, where: "deleted_at IS NULL"
    t.index ["updated_at"], name: "index_motor_forms_on_updated_at"
  end

  create_table "motor_note_tag_tags", force: :cascade do |t|
    t.integer "note_id", null: false
    t.integer "tag_id", null: false
    t.index ["note_id", "tag_id"], name: "motor_note_tags_note_id_tag_id_index", unique: true
    t.index ["tag_id"], name: "index_motor_note_tag_tags_on_tag_id"
  end

  create_table "motor_note_tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "motor_note_tags_name_unique_index", unique: true
  end

  create_table "motor_notes", force: :cascade do |t|
    t.bigint "author_id"
    t.string "author_type"
    t.text "body"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id", "author_type"], name: "motor_notes_author_id_author_type_index"
    t.index ["record_id", "record_type"], name: "motor_notes_record_id_record_type_index"
  end

  create_table "motor_notifications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "recipient_id", null: false
    t.string "recipient_type", null: false
    t.string "record_id"
    t.string "record_type"
    t.string "status", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["recipient_id", "recipient_type"], name: "motor_notifications_recipient_id_recipient_type_index"
    t.index ["record_id", "record_type"], name: "motor_notifications_record_id_record_type_index"
  end

  create_table "motor_queries", force: :cascade do |t|
    t.bigint "author_id"
    t.string "author_type"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "description"
    t.string "name", null: false
    t.text "preferences", null: false
    t.text "sql_body", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "motor_queries_name_unique_index", unique: true, where: "deleted_at IS NULL"
    t.index ["updated_at"], name: "index_motor_queries_on_updated_at"
  end

  create_table "motor_reminders", force: :cascade do |t|
    t.bigint "author_id", null: false
    t.string "author_type", null: false
    t.datetime "created_at", null: false
    t.bigint "recipient_id", null: false
    t.string "recipient_type", null: false
    t.string "record_id"
    t.string "record_type"
    t.datetime "scheduled_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id", "author_type"], name: "motor_reminders_author_id_author_type_index"
    t.index ["recipient_id", "recipient_type"], name: "motor_reminders_recipient_id_recipient_type_index"
    t.index ["record_id", "record_type"], name: "motor_reminders_record_id_record_type_index"
    t.index ["scheduled_at"], name: "index_motor_reminders_on_scheduled_at"
  end

  create_table "motor_resources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.text "preferences", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_motor_resources_on_name", unique: true
    t.index ["updated_at"], name: "index_motor_resources_on_updated_at"
  end

  create_table "motor_taggable_tags", force: :cascade do |t|
    t.integer "tag_id", null: false
    t.bigint "taggable_id", null: false
    t.string "taggable_type", null: false
    t.index ["tag_id"], name: "index_motor_taggable_tags_on_tag_id"
    t.index ["taggable_id", "taggable_type", "tag_id"], name: "motor_polymorphic_association_tag_index", unique: true
  end

  create_table "motor_tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "motor_tags_name_unique_index", unique: true
  end

  create_table "public_knowledge_sources", force: :cascade do |t|
    t.integer "company_id", null: false
    t.datetime "created_at", null: false
    t.text "extracted_text"
    t.datetime "imported_at"
    t.text "last_error"
    t.string "source_kind", null: false
    t.string "status", default: "pending", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["company_id"], name: "index_public_knowledge_sources_on_company_id"
  end

  create_table "support_rules", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.boolean "blocks_public_knowledge", default: false, null: false
    t.string "category", null: false
    t.integer "company_id"
    t.decimal "confidence", precision: 4, scale: 2, default: "0.9", null: false
    t.datetime "created_at", null: false
    t.text "escalation_reason"
    t.text "handoff_note"
    t.string "match_type", null: false
    t.string "name", null: false
    t.integer "priority", default: 100, null: false
    t.string "priority_level", default: "normal", null: false
    t.text "reasoning_summary", null: false
    t.string "route", null: false
    t.text "terms", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "active", "blocks_public_knowledge", "priority"], name: "index_support_rules_on_company_active_blockers_priority"
    t.index ["company_id", "active", "priority"], name: "index_support_rules_on_company_id_and_active_and_priority"
    t.index ["company_id"], name: "index_support_rules_on_company_id"
  end

  create_table "taggings", force: :cascade do |t|
    t.string "context", limit: 128
    t.datetime "created_at", precision: nil
    t.integer "tag_id"
    t.integer "taggable_id"
    t.string "taggable_type"
    t.integer "tagger_id"
    t.string "tagger_type"
    t.string "tenant", limit: 128
    t.index ["context"], name: "index_taggings_on_context"
    t.index ["tag_id", "taggable_id", "taggable_type", "context", "tagger_id", "tagger_type"], name: "taggings_idx", unique: true
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
    t.index ["taggable_id", "taggable_type", "context"], name: "taggings_taggable_context_idx"
    t.index ["taggable_id", "taggable_type", "tagger_id", "context"], name: "taggings_idy"
    t.index ["taggable_id"], name: "index_taggings_on_taggable_id"
    t.index ["taggable_type", "taggable_id"], name: "index_taggings_on_taggable_type_and_taggable_id"
    t.index ["taggable_type"], name: "index_taggings_on_taggable_type"
    t.index ["tagger_id", "tagger_type"], name: "index_taggings_on_tagger_id_and_tagger_type"
    t.index ["tagger_id"], name: "index_taggings_on_tagger_id"
    t.index ["tagger_type", "tagger_id"], name: "index_taggings_on_tagger_type_and_tagger_id"
    t.index ["tenant"], name: "index_taggings_on_tenant"
  end

  create_table "tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "taggings_count", default: 0
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_tags_on_name", unique: true
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
    t.boolean "manual_takeover", default: false, null: false
    t.string "priority"
    t.boolean "processing", default: false, null: false
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
  add_foreign_key "knowledge_chunks", "companies"
  add_foreign_key "knowledge_chunks", "manual_knowledge_entries"
  add_foreign_key "knowledge_chunks", "public_knowledge_sources"
  add_foreign_key "manual_knowledge_entries", "companies"
  add_foreign_key "messages", "tickets"
  add_foreign_key "motor_alert_locks", "motor_alerts", column: "alert_id"
  add_foreign_key "motor_alerts", "motor_queries", column: "query_id"
  add_foreign_key "motor_note_tag_tags", "motor_note_tags", column: "tag_id"
  add_foreign_key "motor_note_tag_tags", "motor_notes", column: "note_id"
  add_foreign_key "motor_taggable_tags", "motor_tags", column: "tag_id"
  add_foreign_key "public_knowledge_sources", "companies"
  add_foreign_key "support_rules", "companies"
  add_foreign_key "taggings", "tags"
  add_foreign_key "tickets", "companies"
  add_foreign_key "tickets", "customers"
  add_foreign_key "tool_calls", "agent_runs"
  add_foreign_key "tool_calls", "tickets"
end
