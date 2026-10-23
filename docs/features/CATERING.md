# Stravování a kuchyň

## Stravování rezervací

V rezervaci lze vybrat **Stravování nevyplněno**, **Bez stravy**, **Polopenze**
nebo **Plná penze**. Původní rezervace a rezervace z iCal importu zůstávají
nevyplněné. Pro penzi je potřeba zadat datum odjezdu, dospělé a děti ke
stravování (včetně nul) a první/poslední jídlo v den příjezdu/odjezdu.
Polopenze zahrnuje snídani a večeři. Jeden režim a stejné počty platí pro celý pobyt.
Přepnutí na bez stravy nebo nevyplněno odstraní původní údaje o porcích a hranicích jídel.

Detail rezervace, týdenní plánovač i tisk počítají skutečné porce pro každé jídlo
samostatně, včetně posledního jídla v den odjezdu. Počty jsou nezávislé na faktuře,
obsazenosti a textu menu; dětské porce se zde nezmenšují koeficientem.
Například pátek–neděle, večeře–snídaně, 10 dospělých a 5 dětí s plnou penzí
znamená 15 pátečních večeří, 15 sobotních snídaní/obědů/večeří a 15 nedělních snídaní.

Zrušené a smazané rezervace se nepočítají; dokončené zůstávají v historii.
Nevyplněné rezervace jsou uvedeny v upozornění s odkazem na doplnění a součty
příslušných dnů jsou označené jako neúplné. Receptury, přepočty spotřeby a nákup
popisují další části tohoto návodu. Smíšené režimy a denní výjimky zatím
implementované nejsou.

## Varianty menu a jídelníčky skupin

V **Meal Planner → Varianty menu** vytvořte rozpis podle dnů pobytu. Počet dnů
zahrnuje příjezd i odjezd (3 dny = 2 noci). Nastavte penzi, první a poslední
jídlo, aktualizujte rozpis a doplňte hlavní jídlo nebo bufet pro každé podání.
Polévky, přílohy a dezerty patří do doplňků daného jídla; počet podání nezvyšují.
Editor podporuje pobyty na 1–366 dnů. Starší jednodenní textové šablony zůstávají dostupné samostatně.

Tlačítko **Přidat varianty z podkladové tabulky** výslovně načte devět variant
z uloženého podkladu Drive ze dne 21. 10. 2026. Data jsou v
`priv/menu_variants/drive_reference.json` včetně odkazu na zdroj. Snídaně jsou
zastoupené textem „Snídaňový bufet“. Existující názvy včetně archivovaných se
přeskočí; import je opakovatelný a žádné dosavadní menu nepřepisuje. Tabulka na
Drive se nemění a aplikace na ní při běžném provozu není závislá. Receptury,
suroviny, množství a hosté se tímto tlačítkem neimportují.

V detailu rezervace otevřete **Menu rezervace**, vyberte variantu a zobrazte
náhled konkrétních dat, jídel a porcí. Varianta musí přesně odpovídat délce,
penzi i prvnímu a poslednímu jídlu. Náhled upozorní na odlišné společné menu i
souběžná menu jiných skupin. Použití mění pouze jídelníček dané rezervace;
společný denní plán a ostatní skupiny zachová. Pokud se od náhledu změní
podklady, aplikace vyžádá nový náhled.

Přiřazený jídelníček je samostatná kopie. Pozdější úprava nebo archivace
varianty ho nepřepíše. Jídla lze ručně upravit; tato úprava je při dalším použití
varianty chráněná. Pro její nahrazení použijte **Povolit přepsání při použití
varianty** a znovu zkontrolujte náhled. Ručně upravené jídlo mimo nový rozpis
zablokuje použití varianty, dokud jeho přepsání výslovně nepovolíte.

Po změně termínu, penze nebo prvního/posledního jídla se uložený jídelníček označí
k nové kontrole a do kuchyňského přehledu se nepoužívá, dokud znovu neprojdete
náhled a použití odpovídající varianty. Samotná změna počtů dospělých/dětí porce
přepočítá rovnou. Plánovač i tisk zobrazují každou skupinu zvlášť, včetně
odjezdové snídaně. Celkové porce nahoře již zahrnují jednotlivé skupiny; nesčítejte
je znovu. Rezervace bez přiřazené varianty nebo se změněným rozpisem mají upozornění.

## Receptury a suroviny

V **Meal Planner → Recepty a suroviny** je knihovna receptů s hledáním bez diakritiky,
katalog surovin a přepočet pro dospělé a děti. U receptu se zadává počet porcí z jedné
dávky a množství všech surovin na tuto dávku. Formulář umožňuje přidávat a odebírat
suroviny přímo v receptu, upravit zdroj či odkaz a uchovat poznámky k pracovním odhadům.

Migrace `20261021210000` automaticky načte verzovaný snímek tabulky z
`priv/recipes/drive_reference.json`: **56 receptur, 172 surovin a 600 řádků receptur**.
Zachovává dávky, množství, jednotky, kategorie, zdroje, poznámky i údaje o nákupním
balení. Google Sheets nijak nemění a aplikace na jejich dostupnosti nezávisí.
Vzorce jsou převzaté jako vypočtené hodnoty ke dni snímku; například odvozené
suroviny lasagní se později nepřepočítávají podle jiné receptury automaticky.
Import proběhne při nasazení a spuštění migrací, žádné ruční kopírování v UI není nutné.

U uloženého jídla varianty nebo rezervace klikněte na **Recepty a suroviny**.
Vyberte jeden hlavní recept a případné doplňky (například polévku). Každý doplněk
se počítá pro stejnou skupinu a nezvyšuje počet vydávaných porcí. Shodné názvy
z tabulky se propojí automaticky; ostatní texty a snídaňové bufety bez receptu
zobrazují upozornění na neúplný výpočet. Text menu se při výběru receptu nemění. Pozdější změna textu hlavního jídla
nebo doplňků odpojí příslušné recepty, aby nezůstalo množství pro jiné jídlo.
Při použití varianty se vazby zkopírují do menu rezervace; ruční změna vazeb
rezervace je chráněná stejně jako ruční úprava jejího menu. Různé skupiny mohou
mít různé recepty a vlastní přepočet surovin.

**Porce dětí** nastavují samostatně koeficient pro teplá jídla a snídaně, obojí
výchozí **70 %** podle tabulky. Počet porcí pro výdej je stále dospělí + děti.
Suroviny používají `(dospělí + děti × koeficient) / porcí v dávce`.
Převádí se pouze g na kg a ml na l; kusy, hmotnost a objem se vzájemně nepřevádějí.
Používané surovině nelze změnit základní jednotku. Výpočet používá aktuální receptury
a přesná desetinná čísla, zaokrouhluje se až zobrazení. Není to historická kalkulace ceny.
Nákupní seznam a balení popisuje následující část; rezervy a sklad se zde nepoužívají.

Testy pokrývají úplnost importu, receptury a suroviny, přepočty, ochranu při
souběžných úpravách, vazby variant a rezervací i ovládání knihovny přes LiveView.
Spusťte `PGUSER=elixir PGPASSWORD='' mix precommit`.


## Nákup pro kuchyň

Otevřete **Meal Planner → Nákupní seznam**, případně **Nákup pro pobyt** v detailu
rezervace. Výchozí období je nejbližší pátek až neděle. Nastavte první a poslední
den (včetně) a vyberte jednu skupinu nebo všechny skupiny. Období může mít až 366 dnů.
Odkaz zachovává období i skupinu a lze ho uložit do záložek.

Seznam sčítá aktuální recepty hlavních chodů i doplňků všech skutečně podávaných
jídel. Respektuje příjezd, odjezd, penzi a samostatné dětské koeficienty pro
teplá jídla a snídaně. **Na co surovinu potřebujete?** rozbalí množství podle
receptů, konkrétního jídla, data a skupiny. Odkaz na recept otevře kalkulačku se
stejným počtem dospělých a dětí i koeficientem jako v daném jídle.

Primární množství je určeno k nákupu; přesná spotřeba zůstává viditelná pod ním.
Pro způsob **Sezona / Na celé období** se až po celkovém součtu zaokrouhlí počet
balení nahoru: `ROUNDUP(ROUND(spotřeba / balení; 10); 0)`, stejně jako v tabulce.
Volitelná velikost balení je v základní jednotce suroviny (kg/l/ks). **Průběžně**
se zobrazuje samostatně jako spotřeba pro zvolené období, bez sezonního
zaokrouhlování balení. Kusy k nákupu se zaokrouhlují nahoru na celé kusy.
Způsob nákupu a velikost balení lze změnit přímo u položky nebo v katalogu surovin.
Bez rezervy a bez odečítání skladu; modul nezakládá skladové ani finanční doklady.

Chybějící stravování, menu, recepty, doplňky nebo nákupní nastavení jsou viditelné
v upozornění s odkazem na opravu. Menu po změně termínu či penze se nezapočítá,
dokud není znovu potvrzené. Zrušené, odstraněné a výslovně nestravované pobyty
jsou vynechány. Po opravě podkladů použijte **Přepočítat z aktuálního menu**.
Pokud je vybraná rezervace nově nedostupná, starý seznam se již nezobrazí.

Odškrtávání se ukládá pouze v daném prohlížeči pro konkrétní období a skupinu;
nejde o sdílené označení nákupu pro celou obsluhu. Přežije hledání i obnovení
stránky. Změna množství, balení nebo zdrojů položky její odškrtnutí zruší.
Bez dostupného úložiště prohlížeče funguje odškrtávání alespoň během otevření
stránky. **Tisk celého seznamu** zahrnuje všechny položky zvoleného období a
skupiny, včetně upozornění; vyhledávací filtry se do tisku nepřenášejí.

### Snídaňový bufet pro první víkend

Migrace `20261021220000` přidá upravitelný recept **Snídaňový bufet** a propojí
stejnojmenné snídaně ve variantách i uložených menu, pokud ještě recept nemají.
Existující vlastní recept ani explicitní vazby nepřepíše. Původní list Bufet
obsahoval pouze názvy a jednotky; uživatel schválil doplnění rozumných pracovních
odhadů pro první vyzkoušení. Tyto hodnoty proto nejsou vydávány za množství z tabulky.

Na jednu dospělou snídani: marmeláda 20 g, med 5 g, cereálie 30 g, čaj 1 sáček,
káva 8 g, kakao 5 g, mléko 150 ml, máslo 15 g a pečivo 2 ks. Snídaňový dětský
koeficient se uplatní samostatně. Normy jsou v `priv/recipes/breakfast_buffet.json`.
Před prvním víkendem je zkontrolujte přes **Upravit normy bufetu**; nepoužívané
položky lze nastavit na 0, další suroviny přidat běžným formulářem receptu.
