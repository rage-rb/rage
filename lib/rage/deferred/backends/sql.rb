# frozen_string_literal: true

require "securerandom"

class Rage::Deferred::Backends::SQL
  def initialize(table_name: "rage_deferred_tasks")
    @table_name = table_name.to_s
    @table_created = false
  end

  # Called during boot - keep it fast and safe
  def pending_tasks
    # Return empty during early boot to avoid pool issues
    # Real pending tasks will be loaded later when pool is stable
    []
  end

  def add(context, publish_at: nil, task_id: nil)
    with_connection do
      ensure_table!
      serialized = serialize(context)
      task_id ||= SecureRandom.uuid

      sql = <<~SQL
        INSERT INTO #{@table_name} (task_id, serialized_task, publish_at, status)
        VALUES (?, ?, ?, 'pending')
        ON CONFLICT (task_id) DO UPDATE SET
          serialized_task = excluded.serialized_task,
          publish_at = excluded.publish_at,
          status = 'pending'
      SQL

      connection.execute(ActiveRecord::Base.sanitize_sql_array([sql, task_id, serialized, publish_at&.to_i]))
      task_id
    end
  end

  # When task is completed (success or final failure) → delete the row
  def remove(task_id)
    with_connection do
      ensure_table!
      sql = ActiveRecord::Base.sanitize_sql_array([
        "DELETE FROM #{@table_name} WHERE task_id = ?",
        task_id
      ])
      connection.execute(sql)
    end
  end

  private

  def with_connection(&block)
    ActiveRecord::Base.with_connection(&block)
  end

  def connection
    ActiveRecord::Base.connection
  end

  def ensure_table!
    return if @table_created

    connection.execute("PRAGMA busy_timeout = 15000;")

    connection.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS #{@table_name} (
        task_id VARCHAR(255) PRIMARY KEY,
        serialized_task TEXT NOT NULL,
        publish_at BIGINT,
        status VARCHAR(20) NOT NULL DEFAULT 'pending'
      )
    SQL

    @table_created = true
  end

  def serialize(context)
    Marshal.dump(context).dump
  end

  def deserialize(data)
    Marshal.load(data.undump)
  end
end
