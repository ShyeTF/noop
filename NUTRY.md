# Nutry — branche `nutry` de ce fork

Ce dépôt est le fork `ShyeTF/noop` de [ryanbr/noop](https://github.com/ryanbr/noop).

## Rôle

- Branche **`main`** : miroir amont (ne pas y mettre les rustines Nutry).
- Branche **`nutry`** : pin amont vérifié **+** rustines Nutry (pas de phone-home GitHub, CTA TestFlight, etc.).

L’application Nutry **ne se met pas à jour** en allant lire GitHub. Les mises à jour utilisateurs passent par **TestFlight Nutry** après sync manuelle.

## Workflow (opérateur / Elon)

1. Léo demande de vérifier une nouvelle version amont (`ryanbr/noop`).
2. Audit changelog / diff / risques réseau.
3. Merger l’amont dans ce fork, puis rebaser / merger dans **`nutry`** en conservant les rustines.
4. Lancer le sync Vendor dans `ShyeTF/Nutry` (`scripts/sync-noop-from-fork.sh` / doc `docs/NOOP_FORK_SYNC.md`).
5. PR Nutry → GitHub Actions TestFlight.

## Rustines présentes sur `nutry`

- `Strand/System/UpdateChecker.swift` — pas d’IPA GitHub ryanbr/noop
- `Strand/System/UpdateAvailability.swift` — pas de contrôle auto GitHub
- `Strand/Screens/SettingsView.swift` — CTA Nutry / TestFlight
- `Strand/Onboarding/OnboardingWizard.swift` — attentes TestFlight

## Réseau

Autorisé côté produit Nutry : API Nutry + Bluetooth bracelet WHOOP.  
Apple Watch : lecture **Apple Santé (HealthKit)** uniquement (pas BLE Watch pour ces métriques).  
Interdit : export HTTP arbitraire, WHOOP cloud, màj GitHub in-app.
