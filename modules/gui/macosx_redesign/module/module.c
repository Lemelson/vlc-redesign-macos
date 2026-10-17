/*****************************************************************************
 * module.c: macosx_redesign module descriptor
 *****************************************************************************
 * Copyright (C) 2026 VLC Redesign contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *****************************************************************************/

/*
 * The redesigned macOS interface (redesign/docs/ARCHITECTURE.md §1.2).
 *
 * - "interface" score 220: above the stock macosx interface (200) and Qt (151), so
 *   VLC.app picks it without --intf. It replaces the stock GUI at build time
 *   (--disable-macosx), they are never installed together (§1.3).
 * - "vout window" score 150: above the stock provider (100), minimal_macosx (50) and
 *   window_macosx (10/1). It only accepts windows while our interface runs.
 */

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_window.h>

#include "MXRModule.h"

vlc_module_begin()
    set_shortname("macOS (redesign)")
    set_description(N_("macOS interface (redesign)"))
    add_shortcut("macosx_redesign", "mxr")
    set_capability("interface", 220)
    set_callbacks(MXROpenIntf, MXRCloseIntf)
    set_subcategory(SUBCAT_INTERFACE_MAIN)
    /* The Objective-C and Swift runtimes cannot be dlclose()d (stock macosx does the same). */
    cannot_unload_broken_library()

    /* Options use the catalog's exact names, so CLI and vlcrc share the Swift UI schema. */
#include "MXRAppOptions.inc"

    add_submodule()
        set_description(N_("macOS redesign video output provider"))
        set_capability("vout window", 150)
        set_callback(MXRWindowOpen)
vlc_module_end()
