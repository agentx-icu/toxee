# toxee Documentation
> Language: [Chinese](README.md) | [English](README.en.md)

## Recommended reading path (by role)

- **New users (just want to run)**  
  [Main README](../README.md) “5-minute overview” + “Quick start” → full steps: [getting-started.md](getting-started.en.md); if issues → [operations/DEPENDENCY_BOOTSTRAP.en.md](operations/DEPENDENCY_BOOTSTRAP.en.md) → [TROUBLESHOOTING.en.md](TROUBLESHOOTING.en.md).

- **Integrators (integrating Tim2Tox into your client)**  
  [Main README](../README.md) “Relationship with Tim2Tox” → [integration/INTEGRATION_GUIDE.md](integration/INTEGRATION_GUIDE.en.md) → [architecture/HYBRID_ARCHITECTURE.md](architecture/HYBRID_ARCHITECTURE.en.md) → (optional) [reference/CALLING_AND_EXTENSIONS.md](reference/CALLING_AND_EXTENSIONS.en.md), [Tim2Tox docs](https://github.com/agentx-icu/tim2tox) ([local doc](../third_party/tim2tox/doc/README.en.md)) INTEGRATION_OVERVIEW / API.

- **Maintainers (change code, debug, release)**  
  [Main README](../README.md) “Current architecture overview” → Maintainer index below → [architecture/MAINTAINER_ARCHITECTURE.md](architecture/MAINTAINER_ARCHITECTURE.en.md) → [reference/IMPLEMENTATION_DETAILS.md](reference/IMPLEMENTATION_DETAILS.en.md), [reference/ACCOUNT_AND_SESSION.md](reference/ACCOUNT_AND_SESSION.en.md) → for build/debug: [operations/BUILD_AND_DEPLOY.en.md](operations/BUILD_AND_DEPLOY.en.md), [operations/DEPENDENCY_BOOTSTRAP.en.md](operations/DEPENDENCY_BOOTSTRAP.en.md), [TROUBLESHOOTING.en.md](TROUBLESHOOTING.en.md), [operations/PATCH_MAINTENANCE.en.md](operations/PATCH_MAINTENANCE.en.md).

---

## Maintainer index

- [architecture/MAINTAINER_ARCHITECTURE.md](architecture/MAINTAINER_ARCHITECTURE.en.md) - **Maintainer view**: hybrid architecture design, dual-path rationale, module roles, init order, easy-to-break spots, reading order
- [architecture/ARCHITECTURE.md](architecture/ARCHITECTURE.en.md) - Overall client architecture, core components and data flow
- [architecture/HYBRID_ARCHITECTURE.md](architecture/HYBRID_ARCHITECTURE.en.md) - Current hybrid architecture responsibilities and callback paths
- [reference/ACCOUNT_AND_SESSION.md](reference/ACCOUNT_AND_SESSION.en.md) - Account init, switch, logout, delete lifecycle
- [reference/IMPLEMENTATION_DETAILS.md](reference/IMPLEMENTATION_DETAILS.en.md) - Key modules and message/event handling implementation details
- [reviews/2026-05-26-core-feature-review.md](reviews/2026-05-26-core-feature-review.md) - Core feature review, fixes, verification scope, and limitations from this pass

## Operations and build

- [getting-started.md](getting-started.en.md) - Clone to run (recommended for first run)
- [operations/BUILD_AND_DEPLOY.md](operations/BUILD_AND_DEPLOY.en.md) - Local build flow, package outputs, GitHub Actions packaging and Release publishing
- [operations/DEPENDENCY_BOOTSTRAP.en.md](operations/DEPENDENCY_BOOTSTRAP.en.md) - Bootstrap order and options (required for fresh clone)
- [operations/DEPENDENCY_LAYOUT.en.md](operations/DEPENDENCY_LAYOUT.en.md) - third_party target layout, legacy assumptions
- [operations/PATCH_MAINTENANCE.en.md](operations/PATCH_MAINTENANCE.en.md) - Patch and dependency maintenance, SDK upgrade checklist
- [TROUBLESHOOTING.md](TROUBLESHOOTING.en.md) - Common build, runtime and debugging issues

## Integration and feature guides

- [integration/INTEGRATION_GUIDE.md](integration/INTEGRATION_GUIDE.en.md) - Minimal Tim2Tox integration and init flow
- [reference/CALLING_AND_EXTENSIONS.md](reference/CALLING_AND_EXTENSIONS.en.md) - Calling, plugins, LAN Bootstrap, IRC extensions
- [reference/GROUP_CHAT_GUIDE.md](reference/GROUP_CHAT_GUIDE.en.md) - Group chat lifecycle, persistence and FAQs
- [reference/PLATFORM_SUPPORT.md](reference/PLATFORM_SUPPORT.en.md) - Platform support scope and differences

## Cross-project references

- [Main README](../README.md)
- **Tim2Tox** (upstream repo [https://github.com/agentx-icu/tim2tox](https://github.com/agentx-icu/tim2tox)): [Documentation index](../third_party/tim2tox/doc/README.en.md), [Bootstrap and polling](../third_party/tim2tox/doc/integration/BOOTSTRAP_AND_POLLING.en.md), [API reference](../third_party/tim2tox/doc/api/API_REFERENCE.en.md)

Implementation plans (for agent/developers): [docs/plans/](../docs/plans/). Historical/one-off docs: [archive/](archive/README.en.md).
