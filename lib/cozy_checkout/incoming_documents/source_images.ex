defmodule CozyCheckout.IncomingDocuments.SourceImages do
  @moduledoc "Original input plus bounded overlapping views of long receipts; never resizes the stored original."

  def prepare(%{content_type: "application/pdf"} = doc, _cfg) do
    {:ok,
     [
       %{
         type: "input_file",
         filename: "doklad.pdf",
         file_data: data(doc.original, doc.content_type)
       }
     ], %{"views" => 1, "kind" => "pdf"}}
  end

  def prepare(doc, cfg) do
    detail =
      if String.starts_with?(cfg[:openai_model] || "", ["gpt-6", "gpt-5.6", "gpt-5.5", "gpt-5.4"]),
         do: "original",
         else: "high"

    original = %{
      type: "input_image",
      image_url: data(doc.original, doc.content_type),
      detail: detail
    }

    executable = System.find_executable("magick") || System.find_executable("convert")

    if executable do
      crop(doc, original, detail, executable)
    else
      {:ok, [original],
       %{
         "views" => 1,
         "warning" => "ImageMagick není dostupný; použil se pouze originál bez výřezů"
       }}
    end
  end

  defp crop(doc, original, detail, executable) do
    dir = Path.join(System.tmp_dir!(), "cozy-receipt-" <> Ecto.UUID.generate())
    File.mkdir!(dir)
    File.chmod!(dir, 0o700)

    try do
      input = Path.join(dir, "source")
      File.write!(input, doc.original, [:binary, :exclusive])
      coder = if doc.content_type == "image/png", do: "png:", else: "jpeg:"
      source = coder <> input <> "[0]"

      limits =
        ~w(-limit thread 1 -limit memory 64MiB -limit map 128MiB -limit disk 128MiB -limit time 15)

      case System.cmd(executable, limits ++ [source, "-auto-orient", "-format", "%w %h", "info:"],
             stderr_to_stdout: true
           ) do
        {dimensions, 0} ->
          case String.split(String.trim(dimensions)) |> Enum.map(&Integer.parse/1) do
            [{width, ""}, {height, ""}]
            when width > 0 and height > 0 and width * height <= 40_000_000 ->
              views = if height > width * 2, do: windows(height, width), else: []

              parts =
                Enum.flat_map(Enum.with_index(views, 1), fn {{top, size}, index} ->
                  output = Path.join(dir, "view-#{index}.jpg")

                  case System.cmd(
                         executable,
                         limits ++
                           [
                             source,
                             "-auto-orient",
                             "-crop",
                             "#{width}x#{size}+0+#{top}",
                             "+repage",
                             "-strip",
                             "-quality",
                             "94",
                             "jpeg:" <> output
                           ],
                         stderr_to_stdout: true
                       ) do
                    {_, 0} ->
                      bytes = File.read!(output)

                      if byte_size(bytes) <= 4_000_000 do
                        [
                          %{
                            type: "input_text",
                            text:
                              "Výřez stejného originálu #{index}/#{length(views)}, svislé pixely #{top}–#{top + size}. Překryv nepřepisuj podruhé."
                          },
                          %{
                            type: "input_image",
                            image_url: data(bytes, "image/jpeg"),
                            detail: detail
                          }
                        ]
                      else
                        []
                      end

                    _ ->
                      []
                  end
                end)

              count = Enum.count(parts, &(Map.get(&1, :type) == "input_image"))
              metadata = %{"views" => count + 1, "width" => width, "height" => height}

              metadata =
                if count != length(views),
                  do:
                    Map.put(
                      metadata,
                      "warning",
                      "Některé výřezy nebyly dostupné; zkontrolujte úplnost přepisu"
                    ),
                  else: metadata

              {:ok, [original | parts], metadata}

            _ ->
              {:error, "Obrázek má nepodporované rozměry nebo přesahuje 40 megapixelů"}
          end

        _ ->
          {:error, "Obrázek se nepodařilo bezpečně načíst pro vytěžení"}
      end
    after
      File.rm_rf(dir)
    end
  end

  defp windows(height, width) do
    size = min(height, max(round(width * 1.8), ceil(height / 5)))
    step = max(1, floor(size * 0.85))
    positions = Stream.iterate(0, &(&1 + step)) |> Enum.take_while(&(&1 < height - size))
    (positions ++ [height - size]) |> Enum.uniq() |> Enum.map(&{&1, size})
  end

  defp data(bytes, mime), do: "data:#{mime};base64,#{Base.encode64(bytes)}"
end
