class AddHumanHandoffAvailableToTickets < ActiveRecord::Migration[8.1]
  def change
    add_column :tickets, :human_handoff_available, :boolean, default: false, null: false
  end
end
