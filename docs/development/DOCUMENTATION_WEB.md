# Webová dokumentace

Web je statická HTML varianta existujícího adresáře `docs/`. Markdown zůstává
jediným zdrojem obsahu a PNG/SVG grafy se používají přímo. Menu automaticky
zahrnuje všechny Markdown soubory, rozdělené na návody, integrace, vývoj a plány.
Grafické postupy jsou dostupné hned pod úvodem. Součástí je vyhledávání s českým ovládáním,
obsah aktuální stránky a menu pro mobil.

## Lokální spuštění

Z kořene repozitáře, s Pythonem 3.10 nebo novějším:

```sh
python3 -m venv .venv-docs
.venv-docs/bin/pip install -r requirements-docs.txt
.venv-docs/bin/mkdocs serve
```

Otevřete `http://127.0.0.1:8000`. Úpravy Markdownu se průběžně promítají do náhledu.
Na Windows použijte programy v `.venv-docs\Scripts` místo `.venv-docs/bin`.

## Vytvoření HTML

```sh
.venv-docs/bin/mkdocs build --strict
python3 -m http.server 8000 --directory site
```

Výstup vzniká v ignorovaném adresáři `site/`; obsahuje stránky, vyhledávání
i obrázky a lze ho obsloužit běžným statickým HTTP serverem. Neotevírejte jej
přes `file://`, protože vyhledávání načítá lokální index přes HTTP.
Při hostování v podadresáři zůstávají odkazy relativní. Web nepoužívá vzdálené
fonty, analytiku ani externí službu pro vyhledávání.

CI vytváří stejný výstup jako stažitelný artefakt **documentation-html**.
Stačí jej rozbalit a spustit nad ním HTTP server. Automatické veřejné nasazení
není zapnuté; výstup obsahuje i provozní a technickou dokumentaci.

## Úpravy a odkazy

- Obsah a obrázky upravujte na původních místech v `docs/`, HTML se neudržuje ručně.
- Nový Markdown soubor se automaticky objeví v menu. Odkazy mezi návody se při
  sestavení přeloží na HTML; PNG, SVG a Mermaid soubory se přenesou do výstupu.
- Odkazy mimo `docs/`, například na zdrojový kód nebo hlavní README, se jen
  v HTML variantě přesměrují na soubory v GitHub větvi `main`.
- Vzhled a sestavení upravuje `mkdocs.yml`, `docs/assets/documentation.css`
  a `tools/docs/hooks.py`. Pro změny grafů platí [návod k obnově obrázků](WORKFLOW_DIAGRAMS.md).

Web nevyžaduje spuštěný Phoenix, databázi ani změnu produkční aplikace.
