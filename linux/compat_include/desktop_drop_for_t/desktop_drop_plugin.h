// Compatibility shim: the desktop_drop_for_t pub republish renamed the
// PACKAGE but kept its Linux headers under include/desktop_drop/, while
// flutter's generated_plugin_registrant.cc includes
// <desktop_drop_for_t/desktop_drop_plugin.h>. Forward to the real header
// (resolved via the plugin target's INTERFACE include dir).
#include "desktop_drop/desktop_drop_plugin.h"
