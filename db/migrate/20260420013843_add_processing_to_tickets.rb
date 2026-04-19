class AddProcessingToTickets < ActiveRecord::Migration[8.1]
  def change
    add_column :tickets, :processing, :boolean, null: false, default: false
  end
end
