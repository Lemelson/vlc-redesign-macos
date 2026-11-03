/*****************************************************************************
 * MXRModule.h: entry points of the macosx_redesign plugin (C, no Objective-C)
 *****************************************************************************
 * Copyright (C) 2026 VLC Redesign contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *****************************************************************************/

#ifndef MXR_MODULE_H
#define MXR_MODULE_H

/* Requires <vlc_common.h> and <vlc_window.h>. */

/* Interface (MXRIntf.m). Called on the interface thread. */
int  MXROpenIntf(vlc_object_t *obj);
void MXRCloseIntf(vlc_object_t *obj);

/* "vout window" submodule (MXRVoutWindow.m). */
int  MXRWindowOpen(vlc_window_t *wnd);

/* "sout filter" submodule (MXRMediaServices.m): `#mxr-local-display:<stream chain>` plays the
 * stream's frames on a local display beside the chain ("Play locally while streaming", D060). */
#define MXR_LOCAL_DISPLAY_MODULE "mxr-local-display"
int  MXRLocalDisplayOpen(vlc_object_t *obj);

/* Lets MXRWindowOpen accept windows: set once the interface has started (MXRIntf.m). */
void MXRVoutWindowSetInterfaceStarted(void);

#endif
