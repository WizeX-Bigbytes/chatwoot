class AddTypebotIdToAgentBots < ActiveRecord::Migration[7.1]
  def change
    add_column :agent_bots, :typebot_id, :string
    add_index :agent_bots, :typebot_id
  end
end
