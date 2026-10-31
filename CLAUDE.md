# NetKit — pokyny pro přispěvatele a agenty

Kotlin + Jetpack Compose pro Android, přenositelné jádro v `shared`.
Rozcestník, struktura a sestavení: [README.md](README.md).

- Síťové testy jen ve vlastních nebo výslovně povolených sítích.
- Agent nesmí ovládat fyzický telefon; každý příkaz adb musí mít
  `-s emulator-5554` nebo jiné explicitní `emulator-*`.
- Bez souhlasu neinstalovat systémové balíčky ani komponenty SDK.
- Do repozitáře nepatří přihlašovací údaje, privátní klíče ani podpisový keystore.
- `shared/src/commonMain` nesmí importovat `java.*`, `javax.*`, `android.*`.
  Platformní operace patří za rozhraní; síťové operace jsou zrušitelné,
  s timeoutem a omezenou souběžností.
- UI texty patří do CS a EN resources; stav přes ViewModel a StateFlow.
- Nové závislosti vyžadují ověření oficiální licence a zápis do
  `docs/zavislosti.md`; povoleny Apache-2.0, MIT a BSD.
  Existující výjimky: ISC pouze pro jBCrypt přibalený v JSch a OFL-1.1 pro fonty.
- Nová oprávnění zdůvodnit v `docs/bezpecnost.md`.
- Ověřovat kontroly odpovídající změně; výsledek PASS/FAIL/NOT RUN
  vždy spojit se skutečným během. Emulátor nenahrazuje fyzický test.
- Před merge změny kódu musí diff zkontrolovat nezávislý reviewer.
- Bez výslovného pokynu necommitovat, nepushovat a nic nenasazovat.
  Před destruktivní akcí popsat dopad a vyžádat potvrzení.

## iOS práce (repo `netkit-ios`)

Toto **veřejné** repo slouží k vývoji iOS verze (SwiftUI nad `:shared`). Vydání Androidu
vznikají jinde (`Losminek/netkit`); odsud se nic nevydává ani netaguje.

- **Vše, co se commitne, je po pushi veřejné.** Žádná tajemství, skutečné IP adresy, SSID, MAC,
  hostname, jména osob, absolutní cesty ani výstupy z reálných sítí. Jen syntetická data
  (192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24, 2001:db8::/32, localhost).
- Interní zadání a reporty sem nepatří; report agenta se píše mimo repo.
- Android (`androidApp/`, `androidMain`) se nemění; Android testy, lint a build musí projít beze změny.
- iOS targety `:shared` se deklarují jen na macOS hostu nebo s `-Pnetkit.ios=true`; Linux build bez
  přepínače zůstává jako dnes. `commonMain` bez `java.*`, `javax.*`, `android.*`.
- Ověřuje se v simulátoru na macOS runneru GitHub Actions; žádný Apple účet, podpis pro zařízení
  ani placená služba.
- Nové závislosti jen s permisivní licencí (MIT, Apache-2.0, BSD), každá v `docs/zavislosti.md`
  s verzí, zdrojem a datem ověření.
- Agent nepushuje; práce na větvi `codex/*`, do `main` jen přes PR po revizi.
