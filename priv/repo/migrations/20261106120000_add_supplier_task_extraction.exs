defmodule CozyCheckout.Repo.Migrations.AddSupplierTaskExtraction do
  use Ecto.Migration

  def up do
    alter table(:incoming_extraction_runs) do
      add :supplier_task, :map, null: false, default: %{}
      add :supplier_task_result, :map, null: false, default: %{}
      add :supplier_task_instructions, :text
      add :content_result, :map, null: false, default: %{}
    end

    drop constraint(:incoming_extraction_runs, :incoming_run_state)

    create constraint(:incoming_extraction_runs, :incoming_run_state,
             check:
               "state IN ('pending', 'running', 'completed', 'failed') AND active_step IN ('identify', 'content', 'supplier_task', 'done')"
           )
  end

  def down do
    # Stop unfinished stages before restoring the old constraint.
    execute "UPDATE incoming_extraction_runs SET active_step = 'content', state = 'failed' WHERE active_step = 'supplier_task'"
    drop constraint(:incoming_extraction_runs, :incoming_run_state)

    create constraint(:incoming_extraction_runs, :incoming_run_state,
             check:
               "state IN ('pending', 'running', 'completed', 'failed') AND active_step IN ('identify', 'content', 'done')"
           )

    alter table(:incoming_extraction_runs) do
      remove :supplier_task
      remove :supplier_task_result
      remove :supplier_task_instructions
      remove :content_result
    end
  end
end
