defmodule CozyCheckout.IncomingDocuments.SupplierProfiles do
  @moduledoc "Company-scoped supplier instructions with explicit identity and optimistic revisions."
  import Ecto.Query
  import Ecto.Changeset
  alias CozyCheckout.Repo
  alias CozyCheckout.IncomingDocuments.{SupplierIdentity, SupplierProfile}

  def base_url(url), do: String.trim_trailing(url, "/")

  defp scoped(doc) do
    url = base_url(doc.base_url)

    from p in SupplierProfile,
      where: p.base_url == ^url and p.company_id == ^doc.company_id and is_nil(p.deleted_at)
  end

  # Picker rows contain no instruction bodies; independent of the document list.
  def list(doc),
    do:
      Repo.all(
        from p in scoped(doc),
          order_by: [asc: p.name, asc: p.id],
          select: map(p, [:id, :name, :ic, :dic, :country_code, :revision])
      )

  def get(doc, id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.one(from p in scoped(doc), where: p.id == ^id)
      _ -> nil
    end
  end

  def get(_, _), do: nil

  def resolve(doc, data) do
    identity = SupplierIdentity.normalize(data)

    cond do
      data["ambiguous"] == true ->
        {nil, identity, "Identita vystavitele je nejednoznačná."}

      identity["country_code"] != "CZ" ->
        {nil, identity, "Země není potvrzená jako CZ; použito společné zadání."}

      not SupplierIdentity.valid_ic?(identity["ic"]) ->
        {nil, identity, "Chybí platné české IČO; použito společné zadání."}

      true ->
        profile =
          Repo.one(
            from p in scoped(doc),
              where:
                p.country_code == "CZ" and
                  p.identity_kind == "ic" and p.identity_value == ^identity["ic"]
          )

        cond do
          is_nil(profile) ->
            {nil, identity, "Neznámý dodavatel; použito společné zadání."}

          SupplierIdentity.conflict(Map.from_struct(profile) |> stringify(), identity) ->
            {nil, identity, "DIČ se liší od uloženého profilu; použito společné zadání."}

          true ->
            {profile, identity, "Přesná shoda českého IČO."}
        end
    end
  end

  defp stringify(map), do: Map.new(map, fn {key, value} -> {to_string(key), value} end)

  def identity(profile),
    do: profile |> Map.from_struct() |> stringify() |> SupplierIdentity.normalize()

  def save(doc, profile_id, attrs, expected_revision, confirmed) do
    identity_input =
      Map.merge(
        %{
          "name" => nil,
          "ic" => nil,
          "dic" => nil,
          "country_code" => nil,
          "ambiguous" => false,
          "uncertainties" => []
        },
        Map.take(attrs, ~w(name ic dic country_code))
      )

    with true <- confirmed == true,
         :ok <- SupplierIdentity.validate(identity_input),
         {:ok, key} <- identity_key(attrs),
         true <- is_binary(attrs["instructions"]) and String.length(attrs["instructions"]) <= 8000 do
      profile = get(doc, profile_id)

      cond do
        profile_id not in [nil, ""] and is_nil(profile) ->
          {:error, "Profil nepatří cílové firmě dokladu."}

        profile && profile.revision != expected_revision ->
          {:error, "Instrukce mezitím někdo změnil. Obnovte profil a změny porovnejte."}

        profile && {profile.country_code, profile.identity_kind, profile.identity_value} != key ->
          {:error, "Identitu existujícího profilu nelze přepsat. Potvrďte nový profil."}

        true ->
          persist(profile, doc, attrs, key)
      end
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, "Potvrďte identitu dodavatele; instrukce mají limit 8 000 znaků."}
    end
  end

  defp identity_key(attrs) do
    identity = SupplierIdentity.normalize(attrs)
    country = identity["country_code"]

    case attrs["identity_kind"] || "ic" do
      "ic" ->
        if country == "CZ" and SupplierIdentity.valid_ic?(identity["ic"]),
          do: {:ok, {country, "ic", identity["ic"]}},
          else: {:error, "Pro klíč IČO je potřeba platné české IČO a země CZ."}

      "dic" ->
        dic = identity["dic"] || ""

        if is_binary(country) and Regex.match?(~r/^[A-Z]{2}$/, country) and
             Regex.match?(~r/^[A-Z]{2}[A-Z0-9]{2,20}$/, dic),
           do: {:ok, {country, "dic", dic}},
           else: {:error, "Vyplňte zemi a DIČ včetně prefixu země a potvrďte ruční klíč DIČ."}

      _ ->
        {:error, "Neplatný klíč identity."}
    end
  end

  defp persist(profile, doc, attrs, {country, kind, value}) do
    identity = SupplierIdentity.normalize(attrs)

    changes = %{
      base_url: base_url(doc.base_url),
      company_id: doc.company_id,
      country_code: country,
      identity_kind: kind,
      identity_value: value,
      name: identity["name"],
      ic: identity["ic"],
      dic: identity["dic"],
      instructions: attrs["instructions"]
    }

    changeset =
      (profile || %SupplierProfile{})
      |> change(changes)
      |> validate_length(:name, max: 255)
      |> validate_length(:ic, max: 255)
      |> validate_length(:dic, max: 255)
      |> unique_constraint(:identity_value, name: :incoming_supplier_identity)

    changeset = if profile, do: optimistic_lock(changeset, :revision), else: changeset

    case Repo.insert_or_update(changeset,
           stale_error_field: :revision,
           mode: :savepoint,
           log: false
         ) do
      {:ok, profile} ->
        {:ok, profile}

      {:error, _} ->
        {:error, "Profil už existuje nebo byl mezitím změněn. Načtěte aktuální profil."}
    end
  end
end
