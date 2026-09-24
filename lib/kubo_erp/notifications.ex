defmodule KuboErp.Notifications do
  @moduledoc """
  Puerto y buzon de notificaciones (P-19, ADR-0017).

  `notify/5` **encola** el aviso (`PENDING`) dentro de la transaccion de negocio:
  es una escritura local y rapida, asi que un proveedor lento o caido no puede
  frenar ni revertir una venta. El `Deliverer` lo entrega en segundo plano por el
  canal que devuelva `adapter/0` y deja el resultado en la misma fila (estado,
  intentos, ultimo error): el buzon es cola y auditoria a la vez.
  """

  import Ecto.Query

  alias KuboErp.Repo
  alias KuboErp.Notifications.Notification

  @max_attempts 5

  @callback deliver(Notification.t()) :: :ok | {:error, term()}

  @doc "Adaptador configurado (`KUBO_NOTIFICATIONS_ADAPTER`); por defecto, el buzon."
  def adapter do
    Application.get_env(:kubo_erp, :notifications_adapter, KuboErp.Notifications.Log)
  end

  @doc """
  Encola un aviso para el negocio.

  Se llama dentro de la transaccion que lo provoca: si la operacion se revierte,
  el aviso desaparece con ella (no se avisa de algo que no paso).
  """
  def notify(tenant_id, kind, subject, body, opts \\ []) do
    %Notification{}
    |> Notification.changeset(%{
      tenant_id: tenant_id,
      kind: kind,
      subject: subject,
      body: body,
      recipient: opts[:recipient],
      reference_type: opts[:reference_type],
      reference_id: opts[:reference_id],
      status: "PENDING"
    })
    |> Repo.insert()
  end

  def list(tenant_id, limit \\ 50) do
    Notification
    |> where([n], n.tenant_id == ^tenant_id)
    |> order_by([n], desc: n.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Cola de entrega
  # ---------------------------------------------------------------------------

  @doc "Toma un lote de pendientes bloqueandolos (varios entregadores no se pisan)."
  def pending_batch(limit \\ 10) do
    Notification
    |> where([n], n.status == "PENDING" and n.attempts < ^@max_attempts)
    |> order_by([n], asc: n.inserted_at)
    |> limit(^limit)
    |> lock("FOR UPDATE SKIP LOCKED")
    |> Repo.all()
  end

  @doc "Entrega un lote y devuelve el resumen (entregadas, fallidas, reintentables)."
  def deliver_pending(limit \\ 10) do
    lote = pending_batch(limit)

    Enum.reduce(lote, %{sent: 0, retry: 0, failed: 0}, fn notification, resumen ->
      case deliver(notification) do
        :sent -> %{resumen | sent: resumen.sent + 1}
        :retry -> %{resumen | retry: resumen.retry + 1}
        :failed -> %{resumen | failed: resumen.failed + 1}
      end
    end)
  end

  defp deliver(notification) do
    case adapter().deliver(notification) do
      :ok ->
        notification
        |> Notification.changeset(%{
          status: "SENT",
          sent_at: DateTime.utc_now() |> DateTime.truncate(:second),
          last_error: nil
        })
        |> Repo.update()

        :sent

      {:error, reason} ->
        intentos = notification.attempts + 1
        estado = if intentos >= @max_attempts, do: "FAILED", else: "PENDING"

        notification
        |> Notification.changeset(%{
          status: estado,
          attempts: intentos,
          last_error: reason |> inspect() |> String.slice(0, 300)
        })
        |> Repo.update()

        if estado == "FAILED", do: :failed, else: :retry
    end
  end
end
