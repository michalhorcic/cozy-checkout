# Barvy a téma

Barvy jsou definované v `assets/css/app.css`. Soubor obsahuje paletu Tailwind v
`@theme` i samostatné proměnné tématu daisyUI. Výchozí téma je světlé;
existence definice tmavého tématu sama neznamená, že je celá aplikace pro něj ověřená.

## Paleta

| Rodina Tailwind | Výchozí barva podle komentářů CSS | Použití |
| --- | --- | --- |
| `primary-50` až `primary-900` | `primary-500`: tmavě šedá, #3a3a3a | Text a hlavní akce |
| `secondary-50` až `secondary-900` | `secondary-500`: šalvějová, #c8d5c4 | Pozadí a okraje |
| `tertiary-50` až `tertiary-900` | `tertiary-500`: růžová, #b8826f | Aktivní a vybrané prvky |
| `accent-50` až `accent-900` | `accent-500`: terakotová, #c85a3a | Destruktivní akce |

Skutečné hodnoty jsou v CSS v OKLCH. Sémantické rodiny `success`, `warning`,
`error` a `info` mají základní, `-light` a `-dark` variantu.

Pozor na rozdíl jmen: daisyUI `--color-accent` ve světlém tématu používá
růžovou odpovídající `tertiary-500`, zatímco číslované `accent-*` jsou terakotové.
Změna jen jedné sady proměnných tedy nepřepíše všechny komponenty.

```heex
<div class="bg-secondary-50 border border-secondary-200 text-primary-500">
  <span class="bg-success-light text-success-dark">Zaplaceno</span>
  <span class="bg-warning-light text-warning-dark">Vyžaduje pozornost</span>
</div>
```

## Údržba a ověření

Paletu a proměnné světlého daisyUI tématu je potřeba při změně sladit. Konkrétní
stavy mohou mít vlastní mapování přímo v komponentě; například kalendář mapuje
rezervace ve `status_color/1` a obsazenost ve `occupancy_badge_class/1` v
`lib/cozy_checkout_web/live/booking_live/calendar.ex`.

Sdílené komponenty jsou v `lib/cozy_checkout_web/components/`. Po změně barev
zkontrolujte kontrast a rozlišení aktivních, neaktivních, chybových a finančních
stavů v POS, administraci a formulářích. Samotná definice palety nezaručuje
přístupnost všech kombinací.

Tento průvodce nahrazuje jednorázový `COLOR_UPDATE_SUMMARY.md`. Původní počty
změněných souborů a seznamy hotových úprav nebyly aktuálním přehledem pokrytí;
historie implementace zůstává v Gitu.
