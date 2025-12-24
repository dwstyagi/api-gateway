class RenameChangesToChangeDetailsInAuditLogs < ActiveRecord::Migration[8.0]
  def change
    rename_column :audit_logs, :changes, :change_details
  end
end
