# Sileo — Ning floating dock source edition

This product includes software developed by the Sileo Team.

## Provenance and license

- Upstream: https://github.com/Sileo/Sileo
- Source baseline: `c9f70158a037dc76b91c450e72af2de0514dd3ee`
- Upstream author/copyright: Sileo Team; upstream package maintainer Amy While.
- Modifications: Ning.
- The original BSD 4-Clause `LICENSE` is retained, including attribution and advertising clauses. Existing source copyright notices remain intact.

## Local change

The original `TabBar: UITabBar` is restyled as a floating glass dock using the real five native tab items, localized titles, images and badge views. Geometry: 64pt height, 18pt horizontal margins, 34pt bottom reserve (or larger system safe area), radius 32pt, 4pt pill inset and 56pt pill height. A 260ms stretch + 140ms settle animation captures the current presentation-layer position when interrupted. Horizontal drag is limited to the dock.

Programmatic tab changes and the existing queue remain routed through `UITabBarController` and the pinned LNPopupController dependency. The old WhiteBlur behavior is exempted only under the new dock material surface.

## Build

The repository has one manual-only workflow on `macos-latest`. The original workflows are preserved as text under `.github/upstream-workflows/`; they must not publish to any upstream repository or APT source.

The workflow performs one iOS arm64 compile, signs with `ldid` using upstream jailbreak entitlements, and creates a standard/rootful `Applications/Sileo.app` deb with explicit file modes and Python-built ar/gzip/USTAR containers. This is **not** a RootHide-specific rebuild and not an App Store signing workflow. Existing `org.coolstar.sileo` package / `org.coolstar.SileoStore` bundle identifiers are retained, so installation can replace a matching Sileo installation. It must not be installed without first checking jailbreak/bootstrap compatibility.

Package author/maintainer: `Ning&Amy While`. No automatic installation, reboot, source publication or release creation.

The CI build is not a device runtime test. Actual glass rendering, queue transitions, keyboard, rotation, repeated taps and drag gestures still require device verification.
