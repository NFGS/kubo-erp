defmodule KuboErp.Notifications.Notification do
  @moduledoc "Notificacion del negocio (P-19, ADR-0017)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "notifications" do
    field(:tenant_id, :binary_id)
    field(:kind, :string)
    field(:channel, :string, default: "LOG")
    field(:recipient, :string)
    field(:subject, :string)
    field(:body, :string)
    field(:status, :string, default: "SENT")
    field(:reference_type, :string)
    field(:reference_id, :binary_id)
    field(:sent_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [
      :tenant_id,
      :kind,
      :channel,
      :recipient,
      :subject,
      :body,
      :status,
      :reference_type,
      :reference_id,
      :sent_at
    ])
    |> validate_required([:tenant_id, :kind, :subject, :body])
    |> validate_length(:subject, max: 200)
  end
end
