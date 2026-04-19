class AddManualTakeoverToTickets < ActiveRecord::Migration[8.1]
  def change
    add_column :tickets, :manual_takeover, :boolean, default: false, null: false
  end
end
