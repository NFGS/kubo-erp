defmodule KuboErp.Mailer do
  @moduledoc "Envio de correo (P-19): Swoosh con el adaptador configurado en runtime."

  use Swoosh.Mailer, otp_app: :kubo_erp
end
