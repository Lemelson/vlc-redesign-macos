/*****************************************************************************
 * MXRSwiftEntry.h: C declarations of the Swift entry points (Sources/MXRPlugin)
 *****************************************************************************
 * Copyright (C) 2026 VLC Redesign contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *****************************************************************************/

#ifndef MXR_SWIFT_ENTRY_H
#define MXR_SWIFT_ENTRY_H

/*
 * Implemented in Swift with @_cdecl (Sources/MXRPlugin/MXRPluginEntry.swift) and linked from
 * libMXRPlugin.a (force-loaded). Not part of the SwiftPM module, so there is no name clash
 * (ARCHITECTURE.md §7.2). Both are called on the main thread.
 */

/* Builds the Swift side: backends, menu, windows. `interfaceBridge` is an
 * MXRInterfaceBridge *, passed unretained (the caller keeps it alive until MXRSwiftStop).
 * Sets the bridge's videoSurfaceProvider. Returns 0 on success. */
int MXRSwiftStart(void *interfaceBridge);

/* Tears the Swift side down: closes windows, drops every reference to the bridge. */
void MXRSwiftStop(void);

#endif
