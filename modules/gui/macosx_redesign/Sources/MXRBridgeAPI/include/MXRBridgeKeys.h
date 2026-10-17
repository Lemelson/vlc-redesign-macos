/*****************************************************************************
 * MXRBridgeKeys.h: names shared by the Objective-C bridge and the Swift adapters
 *****************************************************************************
 * Copyright (C) 2026 VLC Redesign contributors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *****************************************************************************/

/*
 * Interim typing of the Foundation boundary (review finding ARC-14): one list of
 * service, topic and snapshot key names, compiled once (MXRBridgeKeys.m) and imported
 * by both sides. Swift sees them as `MXRBridgeService.playerVolume`,
 * `MXRPlayerKey.volume`, ... so a renamed key fails to compile instead of silently
 * reading a default.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Names delivered to `-[MXRServicesEventSink bridgeServiceDidChange:]`.
///
/// The player is split into topics: each engine callback re-reads only its topic.
/// `player` means "every player topic" (initial state, reset).
typedef NSString *MXRBridgeService NS_TYPED_EXTENSIBLE_ENUM;
extern MXRBridgeService const MXRBridgeServicePlayer;
/// state, rate, buffering, capabilities, error, recording, A-B loop, restore prompt, fullscreen, PiP
extern MXRBridgeService const MXRBridgeServicePlayerState;
/// the current media (and its library fields)
extern MXRBridgeService const MXRBridgeServicePlayerMedia;
extern MXRBridgeService const MXRBridgeServicePlayerTracks;
/// titles, chapters and programs
extern MXRBridgeService const MXRBridgeServicePlayerTitles;
/// audio/subtitle delay, subtitle FPS, subtitle text scale
extern MXRBridgeService const MXRBridgeServicePlayerSync;
/// video/audio effects, subtitle style, track defaults, visualization (vout/aout variables)
extern MXRBridgeService const MXRBridgeServicePlayerEffects;
extern MXRBridgeService const MXRBridgeServicePlayerVolume;
/// audio output devices (listed only on device changes or an explicit refresh)
extern MXRBridgeService const MXRBridgeServicePlayerDevices;
extern MXRBridgeService const MXRBridgeServicePlayerStatistics;
extern MXRBridgeService const MXRBridgeServicePlayerTeletext;
/// a snapshot file was written (`snapshotURL`)
extern MXRBridgeService const MXRBridgeServicePlayerSnapshot;
/// the queue's items (also re-reads the queue state)
extern MXRBridgeService const MXRBridgeServiceQueue;
/// current index, repeat, order, stopped action, hasNext/hasPrevious (everything but the items)
extern MXRBridgeService const MXRBridgeServiceQueueState;
extern MXRBridgeService const MXRBridgeServiceSettings;
extern MXRBridgeService const MXRBridgeServiceShortcuts;
/// one on-screen message for the redesign OSD (the engine OSD is off, D027)
extern MXRBridgeService const MXRBridgeServiceOSD;

extern MXRBridgeService const MXRBridgeServiceLibrary;
extern MXRBridgeService const MXRBridgeServiceLibraryError;
extern MXRBridgeService const MXRBridgeServiceDialogs;
extern MXRBridgeService const MXRBridgeServiceOutput;
extern MXRBridgeService const MXRBridgeServiceExtensions;
extern MXRBridgeService const MXRBridgeServiceRenderers;
extern MXRBridgeService const MXRBridgeServiceMediaSources;
extern MXRBridgeService const MXRBridgeServiceAudioTest;
extern MXRBridgeService const MXRBridgeServiceThumbnails;
extern MXRBridgeService const MXRBridgeServiceWaveform;
extern MXRBridgeService const MXRBridgeServiceSettingsValues;
extern MXRBridgeService const MXRBridgeServiceSettingsSaveFailed;
extern MXRBridgeService const MXRBridgeServiceOperationError;
extern MXRBridgeService const MXRBridgeServiceMediaStale;
extern MXRBridgeService const MXRBridgeServiceQueueFavorites;

/// The only dynamic service namespace: one known settings option.
FOUNDATION_EXPORT MXRBridgeService MXRBridgeServiceForSetting(NSString *option);

/// Public commands; arguments remain Foundation payloads.
typedef NSString *MXRBridgeCommand NS_TYPED_EXTENSIBLE_ENUM;
extern MXRBridgeCommand const MXRBridgeCommandAddExternalTrack;
extern MXRBridgeCommand const MXRBridgeCommandAddFolder;
extern MXRBridgeCommand const MXRBridgeCommandAnswerRestorePrompt;
extern MXRBridgeCommand const MXRBridgeCommandAttachAudioTrack;
extern MXRBridgeCommand const MXRBridgeCommandAttachSubtitle;
extern MXRBridgeCommand const MXRBridgeCommandCancel;
extern MXRBridgeCommand const MXRBridgeCommandCancelWaveform;
extern MXRBridgeCommand const MXRBridgeCommandClear;
extern MXRBridgeCommand const MXRBridgeCommandClearHistory;
extern MXRBridgeCommand const MXRBridgeCommandDiscover;
extern MXRBridgeCommand const MXRBridgeCommandDismiss;
extern MXRBridgeCommand const MXRBridgeCommandInsert;
extern MXRBridgeCommand const MXRBridgeCommandJump;
extern MXRBridgeCommand const MXRBridgeCommandMove;
extern MXRBridgeCommand const MXRBridgeCommandNext;
extern MXRBridgeCommand const MXRBridgeCommandNextFrame;
extern MXRBridgeCommand const MXRBridgeCommandPause;
extern MXRBridgeCommand const MXRBridgeCommandPlay;
extern MXRBridgeCommand const MXRBridgeCommandPlayNow;
extern MXRBridgeCommand const MXRBridgeCommandPostAction;
extern MXRBridgeCommand const MXRBridgeCommandPostLogin;
extern MXRBridgeCommand const MXRBridgeCommandPrevious;
extern MXRBridgeCommand const MXRBridgeCommandRefreshAudioDevices;
extern MXRBridgeCommand const MXRBridgeCommandRemove;
extern MXRBridgeCommand const MXRBridgeCommandRemoveFolder;
extern MXRBridgeCommand const MXRBridgeCommandRescan;
extern MXRBridgeCommand const MXRBridgeCommandReset;
extern MXRBridgeCommand const MXRBridgeCommandResetAll;
extern MXRBridgeCommand const MXRBridgeCommandSave;
extern MXRBridgeCommand const MXRBridgeCommandSeek;
extern MXRBridgeCommand const MXRBridgeCommandSeekPosition;
extern MXRBridgeCommand const MXRBridgeCommandSelect;
extern MXRBridgeCommand const MXRBridgeCommandSelectAudioDevice;
extern MXRBridgeCommand const MXRBridgeCommandSelectChapter;
extern MXRBridgeCommand const MXRBridgeCommandSelectProgram;
extern MXRBridgeCommand const MXRBridgeCommandSelectTeletextPage;
extern MXRBridgeCommand const MXRBridgeCommandSelectTitle;
extern MXRBridgeCommand const MXRBridgeCommandSelectTrack;
extern MXRBridgeCommand const MXRBridgeCommandSet;
extern MXRBridgeCommand const MXRBridgeCommandSetAudioDelay;
extern MXRBridgeCommand const MXRBridgeCommandSetAudioEffects;
extern MXRBridgeCommand const MXRBridgeCommandSetAudioVisualization;
extern MXRBridgeCommand const MXRBridgeCommandSetBindings;
extern MXRBridgeCommand const MXRBridgeCommandSetFavorite;
extern MXRBridgeCommand const MXRBridgeCommandSetFullscreen;
extern MXRBridgeCommand const MXRBridgeCommandSetMediaStoppedAction;
extern MXRBridgeCommand const MXRBridgeCommandSetMuted;
extern MXRBridgeCommand const MXRBridgeCommandSetOrder;
extern MXRBridgeCommand const MXRBridgeCommandSetPauseAtEnd;
extern MXRBridgeCommand const MXRBridgeCommandSetPictureInPicture;
extern MXRBridgeCommand const MXRBridgeCommandSetPlaylistFavorite;
extern MXRBridgeCommand const MXRBridgeCommandSetRate;
extern MXRBridgeCommand const MXRBridgeCommandSetRecording;
extern MXRBridgeCommand const MXRBridgeCommandSetRepeatMode;
extern MXRBridgeCommand const MXRBridgeCommandSetSubtitleDelay;
extern MXRBridgeCommand const MXRBridgeCommandSetSubtitleDurationFactor;
extern MXRBridgeCommand const MXRBridgeCommandSetSubtitleSafeInset;
extern MXRBridgeCommand const MXRBridgeCommandSetSubtitleFPS;
extern MXRBridgeCommand const MXRBridgeCommandSetSubtitleStyle;
extern MXRBridgeCommand const MXRBridgeCommandSetSubtitleTextScale;
extern MXRBridgeCommand const MXRBridgeCommandSetTeletextEnabled;
extern MXRBridgeCommand const MXRBridgeCommandSetTeletextTransparent;
extern MXRBridgeCommand const MXRBridgeCommandSetThumbnailSize;
extern MXRBridgeCommand const MXRBridgeCommandSetTrackDefaults;
extern MXRBridgeCommand const MXRBridgeCommandSetVideoEffects;
extern MXRBridgeCommand const MXRBridgeCommandSetVolume;
extern MXRBridgeCommand const MXRBridgeCommandSetWatched;
extern MXRBridgeCommand const MXRBridgeCommandShowMessage;
extern MXRBridgeCommand const MXRBridgeCommandSort;
extern MXRBridgeCommand const MXRBridgeCommandStart;
extern MXRBridgeCommand const MXRBridgeCommandStop;
extern MXRBridgeCommand const MXRBridgeCommandTakeSnapshot;
extern MXRBridgeCommand const MXRBridgeCommandToggleABLoop;
extern MXRBridgeCommand const MXRBridgeCommandTogglePause;
extern MXRBridgeCommand const MXRBridgeCommandTrigger;
extern MXRBridgeCommand const MXRBridgeCommandUnselectTrack;
extern MXRBridgeCommand const MXRBridgeCommandUnselectTracks;

/// Public requests; arguments remain Foundation payloads.
typedef NSString *MXRBridgeRequest NS_TYPED_EXTENSIBLE_ENUM;
extern MXRBridgeRequest const MXRBridgeRequestActivate;
extern MXRBridgeRequest const MXRBridgeRequestAddBookmark;
extern MXRBridgeRequest const MXRBridgeRequestAddFolder;
extern MXRBridgeRequest const MXRBridgeRequestAddNetworkStream;
extern MXRBridgeRequest const MXRBridgeRequestAllMedia;
extern MXRBridgeRequest const MXRBridgeRequestAppendToPlaylist;
extern MXRBridgeRequest const MXRBridgeRequestArtwork;
extern MXRBridgeRequest const MXRBridgeRequestAttachAudioTrack;
extern MXRBridgeRequest const MXRBridgeRequestAttachSubtitle;
extern MXRBridgeRequest const MXRBridgeRequestBookmarks;
extern MXRBridgeRequest const MXRBridgeRequestBreadcrumb;
extern MXRBridgeRequest const MXRBridgeRequestCancel;
extern MXRBridgeRequest const MXRBridgeRequestCancelWaveform;
extern MXRBridgeRequest const MXRBridgeRequestChildren;
extern MXRBridgeRequest const MXRBridgeRequestChoices;
extern MXRBridgeRequest const MXRBridgeRequestClearHistory;
extern MXRBridgeRequest const MXRBridgeRequestCreatePlaylist;
extern MXRBridgeRequest const MXRBridgeRequestDeactivate;
extern MXRBridgeRequest const MXRBridgeRequestDeletePlaylist;
extern MXRBridgeRequest const MXRBridgeRequestDetails;
extern MXRBridgeRequest const MXRBridgeRequestDiscover;
extern MXRBridgeRequest const MXRBridgeRequestDynamicChoices;
extern MXRBridgeRequest const MXRBridgeRequestHomeSections;
extern MXRBridgeRequest const MXRBridgeRequestImportFiles;
extern MXRBridgeRequest const MXRBridgeRequestInstallAddon;
extern MXRBridgeRequest const MXRBridgeRequestInstallExtension;
extern MXRBridgeRequest const MXRBridgeRequestList;
extern MXRBridgeRequest const MXRBridgeRequestMedia;
extern MXRBridgeRequest const MXRBridgeRequestMenu;
extern MXRBridgeRequest const MXRBridgeRequestModuleDetails;
extern MXRBridgeRequest const MXRBridgeRequestPage;
extern MXRBridgeRequest const MXRBridgeRequestRefreshChildren;
extern MXRBridgeRequest const MXRBridgeRequestRemoveAddon;
extern MXRBridgeRequest const MXRBridgeRequestRemoveBookmark;
extern MXRBridgeRequest const MXRBridgeRequestRemoveExtension;
extern MXRBridgeRequest const MXRBridgeRequestRemoveFolder;
extern MXRBridgeRequest const MXRBridgeRequestRemoveFromPlaylist;
extern MXRBridgeRequest const MXRBridgeRequestRemoveNetworkStream;
extern MXRBridgeRequest const MXRBridgeRequestRenameBookmark;
extern MXRBridgeRequest const MXRBridgeRequestRenameNetworkStream;
extern MXRBridgeRequest const MXRBridgeRequestRenamePlaylist;
extern MXRBridgeRequest const MXRBridgeRequestRescan;
extern MXRBridgeRequest const MXRBridgeRequestSearchAddons;
extern MXRBridgeRequest const MXRBridgeRequestSeekPreview;
extern MXRBridgeRequest const MXRBridgeRequestSetFavorite;
extern MXRBridgeRequest const MXRBridgeRequestSetPlaylistFavorite;
extern MXRBridgeRequest const MXRBridgeRequestSetThumbnailSize;
extern MXRBridgeRequest const MXRBridgeRequestSetWatched;
extern MXRBridgeRequest const MXRBridgeRequestStart;
extern MXRBridgeRequest const MXRBridgeRequestSubtitleCues;
extern MXRBridgeRequest const MXRBridgeRequestTrigger;
extern MXRBridgeRequest const MXRBridgeRequestTriggerMenu;
extern MXRBridgeRequest const MXRBridgeRequestWaveform;

/// Keys of the player topics and of their nested track, title, chapter and program records.
typedef NSString *MXRPlayerKey NS_TYPED_EXTENSIBLE_ENUM;
extern MXRPlayerKey const MXRPlayerKeyState;
extern MXRPlayerKey const MXRPlayerKeyMedia;
extern MXRPlayerKey const MXRPlayerKeyRate;
extern MXRPlayerKey const MXRPlayerKeyBufferingProgress;
extern MXRPlayerKey const MXRPlayerKeyCanPause;
extern MXRPlayerKey const MXRPlayerKeyCanSeek;
extern MXRPlayerKey const MXRPlayerKeyCanChangeRate;
extern MXRPlayerKey const MXRPlayerKeyCanRecord;
extern MXRPlayerKey const MXRPlayerKeyErrorMessage;
extern MXRPlayerKey const MXRPlayerKeyIsRecording;
extern MXRPlayerKey const MXRPlayerKeyABLoop;
extern MXRPlayerKey const MXRPlayerKeyRestorePrompt;
extern MXRPlayerKey const MXRPlayerKeyIsFullscreen;
extern MXRPlayerKey const MXRPlayerKeyIsPictureInPicture;
extern MXRPlayerKey const MXRPlayerKeyAudioTracks;
extern MXRPlayerKey const MXRPlayerKeyVideoTracks;
extern MXRPlayerKey const MXRPlayerKeySubtitleTracks;
extern MXRPlayerKey const MXRPlayerKeyTitles;
extern MXRPlayerKey const MXRPlayerKeyChapters;
extern MXRPlayerKey const MXRPlayerKeySelectedTitleIndex;
extern MXRPlayerKey const MXRPlayerKeySelectedChapterIndex;
extern MXRPlayerKey const MXRPlayerKeyPrograms;
extern MXRPlayerKey const MXRPlayerKeyAudioDelay;
extern MXRPlayerKey const MXRPlayerKeySubtitleDelay;
extern MXRPlayerKey const MXRPlayerKeySubtitleFPS;
extern MXRPlayerKey const MXRPlayerKeySubtitleTextScale;
extern MXRPlayerKey const MXRPlayerKeyVideoEffects;
extern MXRPlayerKey const MXRPlayerKeyAudioEffects;
extern MXRPlayerKey const MXRPlayerKeySubtitleStyle;
extern MXRPlayerKey const MXRPlayerKeyTrackDefaults;
extern MXRPlayerKey const MXRPlayerKeyAudioVisualization;
extern MXRPlayerKey const MXRPlayerKeySubtitleDurationFactor;
extern MXRPlayerKey const MXRPlayerKeyVolume;
extern MXRPlayerKey const MXRPlayerKeyIsMuted;
extern MXRPlayerKey const MXRPlayerKeyAudioDevices;
extern MXRPlayerKey const MXRPlayerKeyCurrentAudioDeviceID;
extern MXRPlayerKey const MXRPlayerKeyStatistics;
extern MXRPlayerKey const MXRPlayerKeyTeletext;
extern MXRPlayerKey const MXRPlayerKeySnapshotURL;
/* Nested records */
extern MXRPlayerKey const MXRPlayerKeyID;
extern MXRPlayerKey const MXRPlayerKeyName;
extern MXRPlayerKey const MXRPlayerKeySelected;
extern MXRPlayerKey const MXRPlayerKeyLanguage;
extern MXRPlayerKey const MXRPlayerKeyCodec;
extern MXRPlayerKey const MXRPlayerKeyWidth;
extern MXRPlayerKey const MXRPlayerKeyHeight;
/// A track loaded from a separate file (sidecar, Add Subtitles, library mapping).
extern MXRPlayerKey const MXRPlayerKeyExternal;
/// The file an external track came from.
extern MXRPlayerKey const MXRPlayerKeyURL;
extern MXRPlayerKey const MXRPlayerKeyIndex;
extern MXRPlayerKey const MXRPlayerKeyLength;
extern MXRPlayerKey const MXRPlayerKeyTime;
extern MXRPlayerKey const MXRPlayerKeyIsMenu;
extern MXRPlayerKey const MXRPlayerKeyScrambled;
extern MXRPlayerKey const MXRPlayerKeyFileName;

/// Keys of the `osd` snapshot.
typedef NSString *MXROSDKey NS_TYPED_EXTENSIBLE_ENUM;
/// The message ("Crop: 2.35:1").
extern MXROSDKey const MXROSDKeyText;
/// `feedback` (result of an action, paired with the pressed key, obeys "Show feedback for
/// shortcuts") or `notice` (file name at start, a failed command; always shown).
extern MXROSDKey const MXROSDKeyKind;
/// Seconds to keep a notice on screen; absent = the user's OSD duration.
extern MXROSDKey const MXROSDKeyDuration;
/// Increments with every message so two identical texts are still two messages.
extern MXROSDKey const MXROSDKeySerial;
extern NSString *const MXROSDKindFeedback;
extern NSString *const MXROSDKindNotice;

/// Keys of the `shortcuts` snapshot.
typedef NSString *MXRShortcutKey NS_TYPED_EXTENSIBLE_ENUM;
extern MXRShortcutKey const MXRShortcutKeyActions;
extern MXRShortcutKey const MXRShortcutKeyID;
/// The engine's human action text (`key-<id>` option text, translated); may be empty.
extern MXRShortcutKey const MXRShortcutKeyName;
extern MXRShortcutKey const MXRShortcutKeyHotkeys;
extern MXRShortcutKey const MXRShortcutKeyGlobal;
/// Bindings of the app-level actions (`macosx-redesign-key-<id>` option values), by option name.
extern MXRShortcutKey const MXRShortcutKeyAppBindings;

NS_ASSUME_NONNULL_END
