# toxee vendored copy

Vendored from pub.dev `record_android` 1.2.1 (hosted sha256
`533ce8afa4e47da5c97ea971cde0f0efec28c9bedfac6257a7a28491d34e07ea`), BSD-3
LICENSE retained. Local patch: `RecorderWrapper.stop` wraps its
MethodChannel.Result in an idempotent decorator — the published plugin can
reply twice from the encoder thread ("Reply already submitted" fatally killed
the whole app during call teardown, observed live on Android). Standalone
build files (example/, nested gradle wrapper/settings) are omitted.
Drop this copy when the record 7.x migration lands with the upstream fix.

---

# record Android

Android specific implementation for record package called by record_platform_interface.