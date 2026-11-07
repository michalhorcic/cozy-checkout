defmodule CozyCheckout.Repo.Migrations.AddAccountStampToOrders do
  use Ecto.Migration

  def change do
    alter table(:orders) do
      add :account_stamp, :string
    end

    create constraint(:orders, :orders_account_stamp_valid,
             check:
               "account_stamp IS NULL OR account_stamp IN ('fox', 'pinecone', 'lantern', 'mushroom', 'spruce', 'key', 'moon', 'mug')"
           )
  end
end
