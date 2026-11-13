//
//  StoryCloudSync.h
//  Frotz
//
//  Two-way sync of a story's saved games between the local Saves folder and the app's iCloud
//  container, so other devices on the same iCloud account can use them.
//  Created by Craig Smith with assistance from Claude Opus/Fable, 11/9/26.
//
//  The local folder (Documents/Saves/<story>.d) stays the one the interpreters read and write;
//  iCloud holds a mirror at <container>/Documents/Saves/<story>.d, the folder iCloud Drive shows
//  as Frotz/Saves. One story's folder is synced at a time: when the story is launched, after each
//  save, and when the Restore dialog opens. Only player-made saves take part; autosave state is
//  per device and stays local.
//
//  Decisions are made by content, as the Dropbox sync does (see dbSyncSingleSaveDir: in
//  StoryMainViewController): each side's hash is compared with the hash both sides had at the
//  last sync (the base, kept per file in Application Support/cloudsync.plist). The side that still
//  matches the base is the one that didn't change. A file changed on both sides, or different
//  with no base, is kept both ways: the local version is renamed "name (iPad, 2026-11-13).ext" and
//  uploaded, iCloud's version comes down under the original name. Deletions propagate in both
//  directions, but only for a file whose surviving copy is unchanged since the last sync, and
//  only within a folder that exists on both sides: a missing folder on either side is treated as
//  never synced, never as a deletion.
//

#import <Foundation/Foundation.h>
#import "iosfrotz.h"

#if EnableCloudSaveSync

NS_ASSUME_NONNULL_BEGIN

@interface StoryCloudSync : NSObject

- (instancetype)initWithLocalSavesPath:(NSString*)savesPath NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

// The Settings switch. Off: nothing is read or written in iCloud, and a sync already under way
// stops at the next file. Atomic: set on the main thread, read on the sync queue.
@property (atomic) BOOL enabled;

// Whether iCloud Drive is usable at all: signed in, and iCloud Drive turned on for Frotz. The
// Settings row is disabled when not.
+ (BOOL)isAvailable;

// Syncs one story's save folder, e.g. "905.z5.d", in the background. `completion` runs on the
// main thread; `changed` is YES if a local save was added, replaced or removed, so a visible
// Restore dialog can refresh.
- (void)syncSaveFolder:(NSString*)subFolder completion:(nullable void (^)(BOOL changed))completion;

// A save was deleted in Frotz: remove the iCloud copy too and forget the file. `subPath` is
// relative to the Saves folder, e.g. "905.z5.d/foo.sav".
- (void)saveDeleted:(NSString*)subPath;

// A story's local save folder was deleted and is about to be recreated empty: forget what was
// synced for it, so its iCloud saves come back down rather than being taken for deleted here.
// See StoryMainViewController forgetSyncRecordsForSaveFolder:.
- (void)forgetSaveFolder:(NSString*)subFolder;

@end

NS_ASSUME_NONNULL_END

#endif // EnableCloudSaveSync
