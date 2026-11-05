defmodule CozyCheckout.IncomingDocuments.SourceImagesTest do
  use ExUnit.Case, async: true
  alias CozyCheckout.IncomingDocuments.SourceImages

  test "PDF keeps all pages in the original file input" do
    assert {:ok, [part], %{"views" => 1}} =
             SourceImages.prepare(%{content_type: "application/pdf", original: "%PDF-test"}, [])

    assert part.type == "input_file"
    assert part.file_data == "data:application/pdf;base64," <> Base.encode64("%PDF-test")
    refute Map.has_key?(part, :detail)
  end

  test "long photos retain the original and receive overlapping labeled views" do
    executable = System.find_executable("magick") || System.find_executable("convert")
    assert executable, "Install ImageMagick (included in the runtime image and CI)"
    {bytes, 0} = System.cmd(executable, ["-size", "200x1600", "xc:white", "jpeg:-"])

    assert {:ok, parts, metadata} =
             SourceImages.prepare(%{content_type: "image/jpeg", original: bytes},
               openai_model: "gpt-6"
             )

    assert hd(parts).image_url == "data:image/jpeg;base64," <> Base.encode64(bytes)
    assert hd(parts).detail == "original"
    assert metadata["width"] == 200
    assert metadata["height"] == 1600
    assert metadata["views"] in 2..8
    assert Enum.count(parts, &(Map.get(&1, :type) == "input_image")) == metadata["views"]
    assert Enum.any?(parts, &(Map.get(&1, :text, "") =~ "Překryv"))
  end

  test "corrupt images are rejected before a paid API call" do
    if System.find_executable("magick") || System.find_executable("convert") do
      assert {:error, _} =
               SourceImages.prepare(%{content_type: "image/png", original: "invalid"}, [])
    end
  end
end
