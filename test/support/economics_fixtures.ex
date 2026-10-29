defmodule CozyCheckout.EconomicsFixtures do
  @moduledoc "Synthetic accounting rows. Never copied from company documents."
  def period, do: %{"code" => "FY-TEST", "from" => "2026-07-01", "to" => "2026-07-31"}

  def catalog do
    [
      account("602001", "Ubytování", "vysledkovy", "vynosy"),
      account("501100", "Potraviny", "vysledkovy", "naklady"),
      account("221001", "Banka", "rozvahovy", "aktivni")
    ]
  end

  def account(code, name, type, kind),
    do: %{
      "kod" => code,
      "nazev" => name,
      "typUctuK" => "typUctu." <> type,
      "druhUctuK" => "druhUctu." <> kind
    }

  def posted do
    [
      movement("602001", "0", "120", "1"),
      movement("501100", "45.50", "0", "2"),
      movement("221001", "120", "45.50", "3")
    ]
  end

  def movement(code, md, dal, id),
    do: %{
      "idUcetniDenik" => id,
      "idDokl" => id,
      "modul" => "INT",
      "ucet" => "code:" <> code,
      "datUcto" => "2026-07-15+02:00",
      "sumTuzMd" => md,
      "sumTuzDal" => dal,
      "zuctovano" => "true",
      "doklad" => "FV-2026-" <> id,
      "nazFirmy" => "Ukázkový odběratel s.r.o.",
      "popis" => "Prodej čaje a limonády",
      "varSym" => "2026001",
      "cisDosle" => "OBJ-001",
      "protiUcet" => "code:311001",
      "protiUcet@showAs" => "311001: Odběratelé",
      "mena" => "code:CZK"
    }

  def trial do
    [
      balance("602001", "0", "120", "0", "120"),
      balance("501100", "45.50", "0", "45.50", "0"),
      balance("221001", "120", "45.50", "174.50", "0")
    ]
  end

  def balance(code, md, dal, closing_md, closing_dal),
    do: %{
      "ucet" => "code:" <> code,
      "ucetniObdobi" => "code:FY-TEST",
      "mena" => "code:CZK",
      "pocatekMd" => if(code == "221001", do: "100", else: "0"),
      "pocatekDal" => "0",
      "obratMdVyb" => md,
      "obratDalVyb" => dal,
      "zustatekMd" => closing_md,
      "zustatekDal" => closing_dal
    }

  def open_item(attrs \\ %{}),
    do:
      Map.merge(
        %{
          "idDokl" => "100",
          "kod" => "FV-2026-100",
          "nazFirmy" => "Ukázková firma s.r.o.",
          "popis" => "Dodávka občerstvení",
          "varSym" => "2026100",
          "cisDosle" => "DOD-100",
          "modul" => "FAV",
          "datUcto" => "2026-07-01+02:00",
          "datSplat" => "2026-07-20+02:00",
          "sumCelkem" => "100",
          "sumCelkemAkt" => "100",
          "juhSumDat" => "25",
          "zbyvaUhradit" => "0",
          "mena" => "code:CZK",
          "storno" => "false"
        },
        attrs
      )
end
