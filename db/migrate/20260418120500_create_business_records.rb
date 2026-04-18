class CreateBusinessRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :business_records do |t|
      t.references :company, null: false, foreign_key: true
      t.string :record_type, null: false
      t.string :external_id, null: false
      t.string :customer_email
      t.string :status, null: false
      t.json :payload, null: false, default: {}

      t.timestamps
    end

    add_index :business_records, [ :company_id, :external_id ], unique: true
  end
end
