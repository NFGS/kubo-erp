defmodule KuboErp.Notifications do
  @moduledoc """
  Puerto de notificaciones (P-19, ADR-0017).

  El nucleo avisa *que* paso (stock bajo, venta del dia); *como* se entrega es
  cosa del adaptador. El de por defecto escribe en el buzon del negocio
  (`notifications`), que sirve de demostracion y de auditoria de lo enviado; un
  proveedor de WhatsApp o de correo se enchufa implementando este contrato.
  """

  import Ecto.Query

  alias KuboErp.Repo
  alias KuboErp.Notifications.Notification

  @callback deliver(map()) :: {:ok, Notification.t()} | {:error, term()}

  @doc "Adaptador configurado (`KUBO_NOTIFICATIONS_ADAPTER`); por defecto, el buzon."
  def adapter do
    Application.get_env(:kubo_erp, :notifications_adapter, KuboErp.Notifications.Log)
  end

  @doc """
  Notifica un hecho del negocio.

  Se llama dentro de la transaccion que lo provoca: si la operacion se revierte,
  el aviso desaparece con ella (no se avisa de algo que no paso).
  """
  def notify(tenant_id, kind, subject, body, opts \\ []) do
    adapter().deliver(%{
      tenant_id: tenant_id,
      kind: kind,
      subject: subject,
      body: body,
      recipient: opts[:recipient],
      reference_type: opts[:reference_type],
      reference_id: opts[:reference_id]
    })
  end

  def list(tenant_id, limit \\ 50) do
    Notification
    |> where([n], n.tenant_id == ^tenant_id)
    |> order_by([n], desc: n.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end
end
