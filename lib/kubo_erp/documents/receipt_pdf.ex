defmodule KuboErp.Documents.ReceiptPdf do
  @moduledoc """
  Comprobante de venta en PDF (P-25, ADR-0018 enmendado).

  Generador minimo y **sin dependencias**: un comprobante es texto en una
  columna, asi que se escribe el PDF a mano (objetos, `xref` con desplazamientos
  reales y fuente Courier con WinAnsi para los acentos). No se introduce un motor
  de PDF —tipografias, imagenes, varias paginas— porque el negocio no lo
  necesita: el comprobante que antes se imprimia desde el navegador ahora queda
  como documento descargable y archivado.

  Formato de ticket de 80 mm: ancho fijo y alto segun el numero de lineas.
  """

  alias KuboErp.Sales.Sale

  @ancho 226
  @linea 11
  @margen 12

  @doc "Renderiza el comprobante de la venta."
  def render(%Sale{} = sale, opts \\ []) do
    lineas = lineas(sale, opts)
    alto = max(320, length(lineas) * @linea + @margen * 2)
    stream = stream_de_texto(lineas, alto)

    objetos = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{@ancho} #{alto}] /Contents 4 0 R " <>
        "/Resources << /Font << /F1 5 0 R >> >> >>",
      "<< /Length #{byte_size(stream)} >>\nstream\n#{stream}\nendstream",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Courier /Encoding /WinAnsiEncoding >>"
    ]

    {:ok, ensamblar(objetos)}
  end

  # ---------------------------------------------------------------------------
  # Contenido del ticket
  # ---------------------------------------------------------------------------

  defp lineas(sale, opts) do
    negocio = opts[:tenant_name] || "Negocio Kubo"
    zona = opts[:timezone] || "America/Bogota"

    [
      centrar(negocio),
      centrar("Comprobante de venta"),
      centrar(sale.number),
      centrar(fecha_hora(sale.inserted_at, zona)),
      separador(),
      "Cliente: #{sale.customer_name || "Consumidor final"}",
      "Pago: #{sale.payment_method}"
    ] ++
      linea_mesa(sale) ++
      [separador()] ++
      Enum.map(sale.items, &linea_item/1) ++
      [
        separador(),
        par("Subtotal", dinero(sale.subtotal)),
        par("IVA", dinero(sale.tax)),
        par("TOTAL", dinero(sale.total)),
        separador(),
        centrar("Gracias por su compra")
      ]
  end

  defp linea_mesa(%Sale{table_number: nil}), do: []
  defp linea_mesa(%Sale{table_number: mesa}), do: ["Mesa: #{mesa}"]

  defp linea_item(item) do
    "#{recortar(item.product_name, 18)} #{item.quantity} x #{dinero(item.unit_price)} = #{dinero(item.total)}"
  end

  defp separador, do: String.duplicate("-", 38)

  defp centrar(texto) do
    relleno = max(div(38 - String.length(texto), 2), 0)
    String.duplicate(" ", relleno) <> texto
  end

  defp par(etiqueta, valor) do
    espacios = max(38 - String.length(etiqueta) - String.length(valor), 1)
    etiqueta <> String.duplicate(" ", espacios) <> valor
  end

  defp recortar(texto, maximo) do
    if String.length(texto) > maximo, do: String.slice(texto, 0, maximo - 1) <> ".", else: texto
  end

  defp dinero(%Decimal{} = valor), do: Decimal.to_string(valor, :normal)
  defp dinero(valor), do: to_string(valor)

  defp fecha_hora(nil, _zona), do: ""

  defp fecha_hora(%DateTime{} = valor, zona) do
    valor
    |> DateTime.shift_zone!(zona)
    |> Calendar.strftime("%Y-%m-%d %H:%M")
  rescue
    _error -> DateTime.to_iso8601(valor)
  end

  defp fecha_hora(%NaiveDateTime{} = valor, zona) do
    valor |> DateTime.from_naive!("Etc/UTC") |> fecha_hora(zona)
  end

  # ---------------------------------------------------------------------------
  # Escritura del PDF
  # ---------------------------------------------------------------------------

  defp stream_de_texto(lineas, alto) do
    lineas
    |> Enum.with_index()
    |> Enum.map_join("\n", fn {linea, indice} ->
      y = alto - @margen - (indice + 1) * @linea
      "BT /F1 8 Tf #{@margen} #{y} Td (#{escapar(linea)}) Tj ET"
    end)
  end

  # El texto va en WinAnsi (Latin-1) y los caracteres con significado en una
  # cadena PDF se escapan.
  defp escapar(texto) do
    texto
    |> :unicode.characters_to_binary(:utf8, :latin1)
    |> String.replace("\\", "\\\\")
    |> String.replace("(", "\\(")
    |> String.replace(")", "\\)")
  end

  # Los desplazamientos del `xref` se calculan sobre los bytes reales: es lo
  # unico que hace que un PDF escrito a mano sea valido.
  defp ensamblar(objetos) do
    {cuerpo, desplazamientos} =
      objetos
      |> Enum.with_index(1)
      |> Enum.reduce({"%PDF-1.4\n", []}, fn {objeto, numero}, {acumulado, desplazamientos} ->
        {acumulado <> "#{numero} 0 obj\n#{objeto}\nendobj\n",
         desplazamientos ++ [byte_size(acumulado)]}
      end)

    total = length(objetos) + 1
    inicio_xref = byte_size(cuerpo)

    xref =
      ["xref\n0 #{total}\n", "0000000000 65535 f \n"] ++
        Enum.map(desplazamientos, fn offset ->
          String.pad_leading(Integer.to_string(offset), 10, "0") <> " 00000 n \n"
        end)

    trailer = "trailer\n<< /Size #{total} /Root 1 0 R >>\nstartxref\n#{inicio_xref}\n%%EOF\n"

    IO.iodata_to_binary([cuerpo, xref, trailer])
  end
end
