//
//  StoryCloudSync.m
//  Frotz
//
//  See StoryCloudSync.h for what this does and the rules it follows.
//

#import "StoryCloudSync.h"

#if EnableCloudSaveSync

#import "ui_utils.h" // FrotzFileContentHash

#define CloudLog(fmt, ...) NSLog(@"iCloud sync: " fmt, ##__VA_ARGS__)

static NSString *const kCloudSyncRecordFile = @"cloudsync.plist";
static NSString *const kRecordHashesKey = @"contentHashes"; // sub path -> hash both sides had at the last sync
static NSString *const kRecordIdentityKey = @"identity";    // the iCloud account the hashes belong to
static const NSTimeInterval kCloudDownloadWait = 30;        // per file, before giving up on it this time

// One side's view of a save file.
@interface CloudSyncEntry : NSObject
@property (nonatomic, copy) NSString *name;   // as spelled on that side
@property (nonatomic, strong) NSURL *url;     // the logical item, downloaded or not
@property (nonatomic) BOOL downloaded;        // iCloud side: the bytes are here
@end
@implementation CloudSyncEntry
@end

@implementation StoryCloudSync {
    NSString *m_savesPath;              // Documents/Saves
    dispatch_queue_t m_queue;           // every sync runs here, one after another
    NSMutableDictionary *m_record;      // cloudsync.plist contents; queue only
    NSMutableSet<NSString*> *m_pendingForgets; // folders whose records are to go before anything else is decided; any thread, under @synchronized
}

- (instancetype)initWithLocalSavesPath:(NSString*)savesPath {
    if ((self = [super init])) {
        m_savesPath = [savesPath copy];
        m_queue = dispatch_queue_create("com.flippencorp.frotz.cloudsync", DISPATCH_QUEUE_SERIAL);
        m_pendingForgets = [NSMutableSet set];
    }
    return self;
}

+ (BOOL)isAvailable {
    return [[NSFileManager defaultManager] ubiquityIdentityToken] != nil;
}

#pragma mark - Which files take part

// Player-made saves only. The autosave state and its window images are per device.
static BOOL IsSyncableSaveName(NSString *name) {
    if ([name hasPrefix: @"."] || [name hasSuffix: @".icloud-download"]) // hidden, or a download of ours that didn't finish
        return NO;
    if ([name isEqualToString: @kFrotzAutoSaveFile] || [name isEqualToString: @kFrotzAutoSavePListFile]
        || [name isEqualToString: @kFrotzOldAutoSaveFile] || [name isEqualToString: @kFrotzAutoSaveFileGlkWin]
        || [name hasPrefix: @kFrotzAutoSaveGlkImgPrefix])
        return NO;
    return YES;
}

#pragma mark - The record of what both sides had

- (NSString*)recordPath {
    NSString *appSuppPath = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES)[0];
    return [appSuppPath stringByAppendingPathComponent: kCloudSyncRecordFile];
}

// Loads the record, and starts over if it was written for a different iCloud account: its hashes
// say what *that* account's copies had, which tells us nothing about this one. Starting over
// loses nothing, since without a base a differing file is kept both ways, never overwritten.
// Records are keyed by lowercased path: the two sides are matched by name without regard to
// case, so the same save can be spelled differently on each, and a key taking one spelling was
// missed when looked up by the other (a deleted save came back because its record wasn't found).
static NSString *RecordKey(NSString *subPath) {
    return [subPath lowercaseString];
}

- (void)loadRecord {
    if (!m_record)
        m_record = [NSMutableDictionary dictionaryWithContentsOfFile: [self recordPath]] ?: [NSMutableDictionary dictionary];
    id<NSObject,NSCopying,NSCoding> token = [[NSFileManager defaultManager] ubiquityIdentityToken];
    NSData *identity = token ? [NSKeyedArchiver archivedDataWithRootObject: token requiringSecureCoding: NO error: nil] : nil;
    NSData *recorded = m_record[kRecordIdentityKey];
    if (identity && recorded && ![identity isEqualToData: recorded]) {
        // The tokens themselves are what the API means to be compared; the archives are only
        // compared first because they usually match byte for byte and save the unarchiving.
        NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingFromData: recorded error: nil];
        unarchiver.requiresSecureCoding = NO;
        id recordedToken = [unarchiver decodeObjectForKey: NSKeyedArchiveRootObjectKey];
        if (![token isEqual: recordedToken]) {
            CloudLog(@"iCloud account changed; forgetting what was synced for the previous one");
            [m_record removeObjectForKey: kRecordHashesKey];
        }
    }
    if (identity)
        m_record[kRecordIdentityKey] = identity;
    if (![m_record[kRecordHashesKey] isKindOfClass: [NSMutableDictionary class]])
        m_record[kRecordHashesKey] = m_record[kRecordHashesKey] ? [m_record[kRecordHashesKey] mutableCopy] : [NSMutableDictionary dictionary];
    // Records written before keys were lowercased (see RecordKey) are folded in once.
    NSMutableDictionary *hashes = m_record[kRecordHashesKey];
    for (NSString *key in [hashes allKeys]) {
        NSString *normalized = RecordKey(key);
        if (![normalized isEqualToString: key]) {
            if (!hashes[normalized])
                hashes[normalized] = hashes[key];
            [hashes removeObjectForKey: key];
        }
    }
}

- (void)saveRecord {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList: m_record format: NSPropertyListBinaryFormat_v1_0 options: 0 error: nil];
    if (data)
        [data writeToFile: [self recordPath] atomically: YES];
}

- (NSString*)baseHashFor:(NSString*)subPath {
    return m_record[kRecordHashesKey][RecordKey(subPath)];
}

- (void)setBaseHash:(NSString*)hash for:(NSString*)subPath {
    if (hash)
        m_record[kRecordHashesKey][RecordKey(subPath)] = hash;
    else
        [m_record[kRecordHashesKey] removeObjectForKey: RecordKey(subPath)];
}

// A story's folder is missing on one side, so it counts as never synced: its old bases go, and
// are saved gone, before anything is copied. Left in place, a transfer that failed or was cut
// short would make the next pass take the file still only on the other side for one deleted here
// (its hash equal to its base), and delete it there too.
- (void)forgetBasesForFolder:(NSString*)subFolder {
    NSString *prefix = RecordKey([subFolder stringByAppendingString: @"/"]);
    NSMutableDictionary *hashes = m_record[kRecordHashesKey];
    NSArray<NSString*> *stale = [[hashes allKeys] filteredArrayUsingPredicate: [NSPredicate predicateWithBlock: ^BOOL(NSString *key, NSDictionary *bindings) {
        return [key hasPrefix: prefix];
    }]];
    if ([stale count]) {
        CloudLog(@"%@: forgetting %lu earlier sync records", subFolder, (unsigned long)[stale count]);
        [hashes removeObjectsForKeys: stale];
        [self saveRecord];
    }
}

#pragma mark - The iCloud side

// nil when iCloud Drive isn't available. Can block the first time, so queue only. Not cached:
// signing out and in again can move it.
- (NSURL*)containerURL {
    return [[NSFileManager defaultManager] URLForUbiquityContainerIdentifier: @kFrotzCloudContainerID];
}

- (NSURL*)cloudSavesURL {
    return [[[self containerURL] URLByAppendingPathComponent: @"Documents"] URLByAppendingPathComponent: @kFrotzSaveDir];
}

// The saves in an iCloud folder, by lowercased name, including ones not downloaded to this
// device (they appear as ".name.icloud" placeholders). nil if the folder can't be listed; an
// empty dictionary if it exists and has none. `exists` says whether the folder is there at all.
- (NSDictionary<NSString*,CloudSyncEntry*>*)cloudEntriesIn:(NSURL*)dir exists:(BOOL*)exists {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableDictionary *entries = [NSMutableDictionary dictionary];
    __block NSArray<NSURL*> *items = nil;
    __block NSError *listError = nil;
    NSError *coordError = nil;
    // Metadata only: listing must not wait for anything to download.
    [[[NSFileCoordinator alloc] initWithFilePresenter: nil] coordinateReadingItemAtURL: dir options: NSFileCoordinatorReadingImmediatelyAvailableMetadataOnly error: &coordError byAccessor: ^(NSURL *readURL) {
        items = [fm contentsOfDirectoryAtURL: readURL includingPropertiesForKeys: @[NSURLIsRegularFileKey] options: 0 error: &listError];
    }];
    BOOL isDir = NO;
    *exists = [fm fileExistsAtPath: dir.path isDirectory: &isDir] && isDir;
    if (!items) {
        if (*exists)
            CloudLog(@"can't list %@: %@", dir.lastPathComponent, coordError ?: listError);
        return nil;
    }
    for (NSURL *item in items) {
        NSString *name = item.lastPathComponent;
        CloudSyncEntry *entry = [[CloudSyncEntry alloc] init];
        if ([name hasPrefix: @"."] && [name hasSuffix: @".icloud"]) { // not downloaded here
            entry.name = [name substringWithRange: NSMakeRange(1, [name length] - 1 - [@".icloud" length])];
            entry.url = [dir URLByAppendingPathComponent: entry.name];
            entry.downloaded = NO;
        } else {
            NSNumber *regular = nil;
            [item getResourceValue: &regular forKey: NSURLIsRegularFileKey error: nil];
            if (![regular boolValue])
                continue;
            entry.name = name;
            entry.url = item;
            entry.downloaded = YES;
        }
        if (IsSyncableSaveName(entry.name))
            entries[[entry.name lowercaseString]] = entry;
    }
    return entries;
}

// Makes sure an iCloud file's bytes are on this device. NO if they didn't arrive in time, in
// which case the file is left alone this round.
- (BOOL)ensureDownloaded:(CloudSyncEntry*)entry {
    if (entry.downloaded)
        return YES;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *error = nil;
    if (![fm startDownloadingUbiquitousItemAtURL: entry.url error: &error]) {
        CloudLog(@"can't start downloading %@: %@", entry.name, error);
        return NO;
    }
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: kCloudDownloadWait];
    while ([deadline timeIntervalSinceNow] > 0 && self.enabled) {
        NSURL *fresh = [NSURL fileURLWithPath: entry.url.path]; // resource values are cached per URL object
        NSString *status = nil;
        [fresh getResourceValue: &status forKey: NSURLUbiquitousItemDownloadingStatusKey error: nil];
        if ([status isEqualToString: NSURLUbiquitousItemDownloadingStatusCurrent] || [status isEqualToString: NSURLUbiquitousItemDownloadingStatusDownloaded]) {
            entry.downloaded = YES;
            return YES;
        }
        [NSThread sleepForTimeInterval: 0.25];
    }
    CloudLog(@"%@ didn't finish downloading in time; leaving it for the next sync", entry.name);
    return NO;
}

// Reads an iCloud file's content hash under coordination. nil if it can't be read.
- (NSString*)hashOfCloudFile:(NSURL*)url {
    __block NSString *hash = nil;
    [[[NSFileCoordinator alloc] initWithFilePresenter: nil] coordinateReadingItemAtURL: url options: NSFileCoordinatorReadingWithoutChanges error: nil byAccessor: ^(NSURL *readURL) {
        hash = FrotzFileContentHash(readURL.path);
    }];
    return hash;
}

// The local file is read first and written in one atomic step, so a failure leaves whatever
// iCloud had in place. Removing the old item and then copying left nothing there if the copy
// failed, which other devices would have taken for a deletion and copied. `overwriting` is NO
// for a file iCloud isn't known to have (a conflict copy, a save only here): if one has appeared
// under that name since the listing, the write fails and the next pass finds both and keeps both.
// `replacing` is the hash iCloud's copy had when the decision was made (only with `overwriting`):
// another device's version can land between that read and this write, and replacing it unseen
// would lose it. Checked inside the coordinated write, where nothing else can change the file;
// if it differs, nothing is written, and the next pass sees the new version and reconciles.
// Returns the hash of the bytes actually uploaded, for the caller to record as the base; the
// local file may have been saved over since the caller hashed it. nil if nothing was written.
- (NSString*)copyLocal:(NSString*)localPath toCloud:(NSURL*)cloudURL overwriting:(BOOL)overwriting replacing:(NSString*)replacing {
    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfFile: localPath options: 0 error: &readError];
    if (!data) {
        CloudLog(@"upload of %@ failed: can't read it: %@", localPath.lastPathComponent, readError);
        return nil;
    }
    __block BOOL ok = NO;
    NSError *coordError = nil;
    [[[NSFileCoordinator alloc] initWithFilePresenter: nil] coordinateWritingItemAtURL: cloudURL options: NSFileCoordinatorWritingForReplacing error: &coordError byAccessor: ^(NSURL *writeURL) {
        NSError *error = nil;
        if (overwriting && replacing && ![(FrotzFileContentHash(writeURL.path) ?: @"") isEqualToString: replacing]) {
            CloudLog(@"%@ changed in iCloud while %@ was being uploaded; leaving it, the next sync will reconcile", cloudURL.lastPathComponent, localPath.lastPathComponent);
            return;
        }
        if (overwriting)
            ok = [data writeToURL: writeURL options: NSDataWritingAtomic error: &error];
        else {
            // NSDataWritingWithoutOverwriting can't be combined with the atomic write, so stage the
            // bytes in a hidden file beside the destination and move them into place: the move won't
            // replace an existing item, and is itself atomic.
            NSFileManager *fm = [NSFileManager defaultManager];
            NSURL *staging = [[writeURL URLByDeletingLastPathComponent] URLByAppendingPathComponent: [NSString stringWithFormat: @".%@.frotz-upload", writeURL.lastPathComponent]];
            [fm removeItemAtURL: staging error: nil];
            ok = [data writeToURL: staging options: 0 error: &error] && [fm moveItemAtURL: staging toURL: writeURL error: &error];
            if (!ok)
                [fm removeItemAtURL: staging error: nil];
        }
        if (!ok)
            CloudLog(@"upload of %@ failed: %@", localPath.lastPathComponent, error);
    }];
    if (coordError)
        CloudLog(@"upload of %@ failed: %@", localPath.lastPathComponent, coordError);
    return ok ? FrotzDataContentHash(data) : nil;
}

// Copies an iCloud file over the local one and returns the content hash of the bytes it copied,
// which is what the caller records as the base: hashing the iCloud file again afterwards could
// see a newer version, and the base would then say the local file holds what it doesn't. nil if
// the copy failed, or if the local file isn't what the decision was made on: `replacing` is the
// hash the local file had then, or nil if there was none. The interpreter and the Dropbox sync
// write to the same folder without going through this queue, and a download wait can be long;
// a save that appeared or changed meanwhile is left alone, and the next pass finds both copies
// and keeps both.
- (NSString*)copyCloud:(NSURL*)cloudURL toLocal:(NSString*)localPath replacing:(NSString*)replacing {
    NSFileManager *fm = [NSFileManager defaultManager];
    __block NSString *hash = nil;
    NSError *coordError = nil;
    [[[NSFileCoordinator alloc] initWithFilePresenter: nil] coordinateReadingItemAtURL: cloudURL options: NSFileCoordinatorReadingWithoutChanges error: &coordError byAccessor: ^(NSURL *readURL) {
        NSError *error = nil;
        NSString *tmp = [[localPath stringByDeletingLastPathComponent] stringByAppendingPathComponent: [NSString stringWithFormat: @".%@.icloud-download", localPath.lastPathComponent]]; // hidden, so neither sync takes a leftover for a save
        [fm removeItemAtPath: tmp error: nil];
        BOOL ok = NO;
        if ([fm copyItemAtURL: readURL toURL: [NSURL fileURLWithPath: tmp] error: &error]) {
            hash = FrotzFileContentHash(tmp); // of the staged bytes, before anything else can touch the file
            NSString *now = [fm fileExistsAtPath: localPath] ? (FrotzFileContentHash(localPath) ?: @"") : nil;
            if ((now == nil) != (replacing == nil) || (now && ![now isEqualToString: replacing])) {
                CloudLog(@"%@ %@ here while it was downloading; leaving it, both will be kept next time", cloudURL.lastPathComponent, replacing ? @"changed" : @"appeared");
                hash = nil;
            } else if (!hash) {
                CloudLog(@"download of %@ failed: the copy couldn't be read back", cloudURL.lastPathComponent);
            } else if (now) {
                // Atomic: the old file is only gone once the new one is in its place, so a failure here
                // leaves the usable copy rather than neither.
                ok = [fm replaceItemAtURL: [NSURL fileURLWithPath: localPath] withItemAtURL: [NSURL fileURLWithPath: tmp]
                           backupItemName: nil options: 0 resultingItemURL: nil error: &error];
            } else
                ok = [fm moveItemAtPath: tmp toPath: localPath error: &error];
        }
        if (!ok) {
            [fm removeItemAtPath: tmp error: nil];
            if (hash || error)
                CloudLog(@"download of %@ failed: %@", cloudURL.lastPathComponent, error);
            hash = nil;
        }
    }];
    if (coordError)
        CloudLog(@"download of %@ failed: %@", cloudURL.lastPathComponent, coordError);
    return hash;
}

// `expecting` is the hash iCloud's copy is believed to have, or nil to delete whatever is there.
// Checked inside the coordinated write: a version from another device that arrived since must
// not be deleted as if it were the one known about. If it can't be read (not downloaded here),
// it isn't deleted either; the next sync downloads it first and decides then.
- (BOOL)deleteCloudFile:(NSURL*)cloudURL expecting:(NSString*)expecting {
    NSFileManager *fm = [NSFileManager defaultManager];
    __block BOOL ok = NO;
    NSError *coordError = nil;
    [[[NSFileCoordinator alloc] initWithFilePresenter: nil] coordinateWritingItemAtURL: cloudURL options: NSFileCoordinatorWritingForDeleting error: &coordError byAccessor: ^(NSURL *writeURL) {
        NSError *error = nil;
        if (expecting && ![(FrotzFileContentHash(writeURL.path) ?: @"") isEqualToString: expecting]) {
            CloudLog(@"%@ in iCloud isn't the version known here; not deleting it, the next sync will reconcile", cloudURL.lastPathComponent);
            return;
        }
        ok = [fm removeItemAtURL: writeURL error: &error];
        if (!ok) { // not downloaded here: the placeholder is what's on disk
            NSURL *placeholder = [[writeURL URLByDeletingLastPathComponent] URLByAppendingPathComponent: [NSString stringWithFormat: @".%@.icloud", writeURL.lastPathComponent]];
            ok = [fm removeItemAtURL: placeholder error: nil];
        }
        if (!ok)
            CloudLog(@"couldn't delete %@ from iCloud: %@", cloudURL.lastPathComponent, error);
    }];
    if (coordError)
        CloudLog(@"couldn't delete %@ from iCloud: %@", cloudURL.lastPathComponent, coordError);
    return ok;
}

#pragma mark - Keeping both versions

// "name (conflict 2026-11-09).ext", or with a counter if that exists too: a local path in `dir`
// whose name is free both there and in `cloudDir` (downloaded or not), since the file is uploaded
// under the same name and must not land on an iCloud save this device hasn't seen yet.
static NSString *UniqueConflictPath(NSString *dir, NSURL *cloudDir, NSString *name) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale localeWithLocaleIdentifier: @"en_US_POSIX"];
    fmt.dateFormat = @"yyyy-MM-dd";
    NSString *date = [fmt stringFromDate: [NSDate date]];
    NSString *stem = [name stringByDeletingPathExtension], *ext = [name pathExtension];
    for (int n = 1; n < 100; n++) {
        NSString *candidate = n == 1 ? [NSString stringWithFormat: @"%@ (conflict %@)", stem, date]
                                     : [NSString stringWithFormat: @"%@ (conflict %@ %d)", stem, date, n];
        if ([ext length])
            candidate = [candidate stringByAppendingPathExtension: ext];
        NSString *path = [dir stringByAppendingPathComponent: candidate];
        NSString *cloudPath = [cloudDir URLByAppendingPathComponent: candidate].path;
        NSString *cloudPlaceholder = [cloudDir URLByAppendingPathComponent: [NSString stringWithFormat: @".%@.icloud", candidate]].path;
        if (![fm fileExistsAtPath: path] && ![fm fileExistsAtPath: cloudPath] && ![fm fileExistsAtPath: cloudPlaceholder])
            return path;
    }
    return nil;
}

// iCloud's own conflicts: two devices wrote the same mirror file before either saw the other's
// version. Each extra version becomes a local "(conflict date)" save, unless its content is
// already here, and is then resolved so iCloud stops tracking it. A version that couldn't be read
// or copied is left unresolved for a later sync, and the versions are only removed once none is
// left; resolving regardless threw away saves that had never been preserved. The new local files
// are uploaded by the main pass, as local-only saves with no base.
- (BOOL)absorbConflictVersionsOf:(CloudSyncEntry*)entry intoLocalDir:(NSString*)localDir knownHashes:(NSSet<NSString*>*)knownHashes {
    NSArray<NSFileVersion*> *versions = [NSFileVersion unresolvedConflictVersionsOfItemAtURL: entry.url];
    if (![versions count])
        return NO;
    BOOL changed = NO;
    for (NSFileVersion *version in versions) {
        NSString *hash = version.URL ? FrotzFileContentHash(version.URL.path) : nil;
        BOOL preserved = hash && [knownHashes containsObject: hash];
        if (hash && !preserved) {
            NSString *dest = UniqueConflictPath(localDir, [entry.url URLByDeletingLastPathComponent], entry.name);
            NSError *error = nil;
            if (dest && [[NSFileManager defaultManager] copyItemAtPath: version.URL.path toPath: dest error: &error]) {
                CloudLog(@"%@ was changed on two devices at once; the other version is kept as %@", entry.name, dest.lastPathComponent);
                preserved = YES;
                changed = YES;
            } else
                CloudLog(@"couldn't keep a conflicting version of %@ (%@); leaving it for the next sync", entry.name, error ?: @"no free name");
        } else if (!hash)
            CloudLog(@"couldn't read a conflicting version of %@; leaving it for the next sync", entry.name);
        // Only this version, now that its content is safe. Sweeping every other version of the
        // file would take a conflict iCloud added while these were being copied, unexamined.
        if (preserved) {
            version.resolved = YES;
            [version removeAndReturnError: nil];
        }
    }
    return changed;
}

#pragma mark - The sync

- (void)syncSaveFolder:(NSString*)subFolder completion:(void (^)(BOOL changed))completion {
    // A folder name has to be a story's: "<story file>.d". With no story open the caller would
    // pass ".d", and once did; that made a stray hidden folder in iCloud.
    BOOL validFolder = [subFolder length] > [@kFrotzGameSaveDirExt length] && [subFolder hasSuffix: @kFrotzGameSaveDirExt]
                       && ![subFolder containsString: @"/"];
    if (!self.enabled || !validFolder) {
        CloudLog(@"%@; not syncing \"%@\"", self.enabled ? @"not a story's save folder" : @"off", subFolder);
        if (completion)
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO); });
        return;
    }
    dispatch_async(m_queue, ^{
        BOOL changed = [self syncSaveFolderNow: subFolder];
        if (completion)
            dispatch_async(dispatch_get_main_queue(), ^{ completion(changed); });
    });
}

// Queue only. Returns whether anything local changed.
- (BOOL)syncSaveFolderNow:(NSString*)subFolder {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (!self.enabled) { // turned off while this pass waited its turn
        CloudLog(@"off; not syncing %@", subFolder);
        return NO;
    }
    if (![self containerURL]) {
        CloudLog(@"iCloud Drive isn't available; not syncing %@", subFolder);
        return NO;
    }
    [self loadRecord];
    [self applyPendingForgets];

    NSString *localDir = [m_savesPath stringByAppendingPathComponent: subFolder];
    NSURL *cloudDir = [[self cloudSavesURL] URLByAppendingPathComponent: subFolder];
    BOOL changed = NO;
    int uploads = 0, downloads = 0, deletions = 0, skipped = 0;
    CloudLog(@"syncing %@", subFolder);

    // The local side. A folder that can't be listed takes no part, so nothing is deleted on its say-so.
    NSError *error = nil;
    NSArray<NSString*> *localNames = [fm contentsOfDirectoryAtPath: localDir error: &error];
    BOOL localExists = localNames != nil;
    const BOOL localExisted = localExists; // as found, for the deletion rule; downloads below may create the folder
    if (!localExists && [fm fileExistsAtPath: localDir]) {
        CloudLog(@"can't list %@: %@", subFolder, error);
        return NO;
    }
    if (!localExists) {
        CloudLog(@"no local folder at %@; taking what iCloud has", localDir);
        [self forgetBasesForFolder: subFolder];
    }

    // The iCloud side. Created if missing: a missing folder means never synced, so everything
    // local is uploaded and nothing is deleted.
    BOOL cloudExisted = NO;
    NSDictionary<NSString*,CloudSyncEntry*> *cloud = [self cloudEntriesIn: cloudDir exists: &cloudExisted];
    if (!cloud) {
        if (cloudExisted)
            return NO; // listing failed; try again next time
        [self forgetBasesForFolder: subFolder];
        if (![fm createDirectoryAtURL: cloudDir withIntermediateDirectories: YES attributes: nil error: &error]) {
            CloudLog(@"can't create %@ in iCloud: %@", subFolder, error);
            return NO;
        }
        CloudLog(@"created %@ in iCloud", subFolder);
        cloud = @{};
    }

    // Fold in any versions iCloud is holding as conflicts, then list local files afresh. The hashes
    // gathered here only say which versions are already present; the decisions below hash each
    // local file again when its turn comes.
    NSMutableSet<NSString*> *localHashes = [NSMutableSet set];
    for (NSString *name in localNames) {
        if (!IsSyncableSaveName(name))
            continue;
        NSString *hash = FrotzFileContentHash([localDir stringByAppendingPathComponent: name]);
        if (hash)
            [localHashes addObject: hash];
    }
    BOOL absorbed = NO;
    for (CloudSyncEntry *entry in [cloud allValues])
        if (entry.downloaded && [self absorbConflictVersionsOf: entry intoLocalDir: localDir knownHashes: localHashes])
            absorbed = YES;
    if (absorbed) {
        changed = YES;
        localNames = [fm contentsOfDirectoryAtPath: localDir error: nil] ?: localNames;
    }
    NSMutableDictionary<NSString*,NSString*> *local = [NSMutableDictionary dictionary]; // lowercased -> actual name
    for (NSString *name in localNames)
        if (IsSyncableSaveName(name))
            local[[name lowercaseString]] = name;

    // Everything not yet on this device starts downloading now, so iCloud fetches the batch in
    // parallel while the files are worked through below; ensureDownloaded then mostly finds them
    // here already. Started one at a time as each was reached, a folder of saves new to this device
    // waited out iCloud's latency once per file.
    for (CloudSyncEntry *entry in [cloud allValues])
        if (!entry.downloaded)
            [fm startDownloadingUbiquitousItemAtURL: entry.url error: nil];

    // Every name on either side, newest first: with a batch to transfer, the saves the player made
    // most recently are the ones another device is likeliest to want, so they are handed to iCloud
    // first (what order it then uploads them in is its own affair, but it tends to follow).
    NSMutableSet<NSString*> *keys = [NSMutableSet setWithArray: [local allKeys]];
    [keys addObjectsFromArray: [cloud allKeys]];
    NSMutableDictionary<NSString*,NSDate*> *modified = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        NSDate *date = nil;
        if (local[key])
            date = [fm attributesOfItemAtPath: [localDir stringByAppendingPathComponent: local[key]] error: nil][NSFileModificationDate];
        else
            [cloud[key].url getResourceValue: &date forKey: NSURLContentModificationDateKey error: nil];
        modified[key] = date ?: [NSDate distantPast];
    }
    NSArray<NSString*> *orderedKeys = [[keys allObjects] sortedArrayUsingComparator: ^NSComparisonResult(NSString *a, NSString *b) {
        NSComparisonResult byDate = [modified[b] compare: modified[a]]; // descending
        return byDate != NSOrderedSame ? byDate : [a compare: b];
    }];
    BOOL completed = YES;
    for (NSString *key in orderedKeys) {
        if (!self.enabled) { // turned off mid-pass; what was done so far is recorded below
            CloudLog(@"turned off; stopping the sync of %@", subFolder);
            completed = NO;
            break;
        }
        NSString *localName = local[key];
        CloudSyncEntry *cloudEntry = cloud[key];
        NSString *name = localName ?: cloudEntry.name;
        NSString *subPath = [subFolder stringByAppendingPathComponent: name];
        NSString *localPath = localName ? [localDir stringByAppendingPathComponent: localName] : [localDir stringByAppendingPathComponent: name];
        NSURL *cloudURL = cloudEntry ? cloudEntry.url : [cloudDir URLByAppendingPathComponent: name];
        [self applyPendingForgets]; // a folder recreated since this pass began has no past, including this one
        NSString *base = [self baseHashFor: subPath];

        if (localName && cloudEntry) {
            if (![self ensureDownloaded: cloudEntry]) {
                skipped++;
                continue;
            }
            NSString *localHash = FrotzFileContentHash(localPath); // read now, not from the pass's start: a download wait above may have been long, and the file may have been saved over meanwhile
            NSString *cloudHash = [self hashOfCloudFile: cloudURL];
            if (!localHash || !cloudHash) {
                CloudLog(@"can't read %@ (%@); leaving it", subPath, localHash ? @"the iCloud copy" : @"the local copy");
                skipped++;
                continue;
            }
            if ([localHash isEqualToString: cloudHash]) {
                [self setBaseHash: localHash for: subPath];
            } else if (base && [localHash isEqualToString: base]) {       // changed in iCloud only
                CloudLog(@"downloading %@", subPath);
                NSString *downloaded = [self copyCloud: cloudURL toLocal: localPath replacing: localHash];
                if (downloaded) {
                    [self setBaseHash: downloaded for: subPath];
                    changed = YES;
                    downloads++;
                }
            } else if (base && [cloudHash isEqualToString: base]) {       // changed here only
                CloudLog(@"uploading %@", subPath);
                NSString *uploaded = [self copyLocal: localPath toCloud: cloudURL overwriting: YES replacing: cloudHash];
                if (uploaded) {
                    [self setBaseHash: uploaded for: subPath];
                    uploads++;
                }
            } else {                                                       // both, or no record: keep both
                NSString *conflictPath = UniqueConflictPath(localDir, cloudDir, localName);
                if (conflictPath && [fm moveItemAtPath: localPath toPath: conflictPath error: nil]) {
                    CloudLog(@"%@ differs here and in iCloud; local version kept as %@", subPath, conflictPath.lastPathComponent);
                    NSString *conflictSub = [subFolder stringByAppendingPathComponent: conflictPath.lastPathComponent];
                    NSString *uploaded = [self copyLocal: conflictPath toCloud: [cloudDir URLByAppendingPathComponent: conflictPath.lastPathComponent] overwriting: NO replacing: nil];
                    if (uploaded) {
                        [self setBaseHash: uploaded for: conflictSub];
                        uploads++;
                    }
                    NSString *downloaded = [self copyCloud: cloudURL toLocal: localPath replacing: nil]; // the local version was just moved aside
                    if (downloaded) {
                        [self setBaseHash: downloaded for: subPath];
                        downloads++;
                    }
                    changed = YES;
                } else
                    CloudLog(@"%@ differs here and in iCloud, but the local version couldn't be set aside; leaving both", subPath);
            }
        } else if (localName) {                                            // here, not in iCloud
            NSString *localHash = FrotzFileContentHash(localPath); // read now, not from the pass's start: a download wait above may have been long, and the file may have been saved over meanwhile
            if (!localHash) {
                CloudLog(@"can't read %@; leaving it", subPath);
                skipped++;
                continue;
            }
            if (base && cloudExisted && [localHash isEqualToString: base]) { // deleted in iCloud, unchanged here
                CloudLog(@"%@ was deleted in iCloud; deleting it here", subPath);
                if ([fm removeItemAtPath: localPath error: nil]) {
                    [self setBaseHash: nil for: subPath];
                    changed = YES;
                    deletions++;
                }
            } else {                                                       // new here, or changed since iCloud lost it
                CloudLog(@"uploading %@", subPath);
                NSString *uploaded = [self copyLocal: localPath toCloud: cloudURL overwriting: NO replacing: nil];
                if (uploaded) {
                    [self setBaseHash: uploaded for: subPath];
                    uploads++;
                }
            }
        } else {                                                           // in iCloud, not here
            if (base && localExisted) {
                if (![self ensureDownloaded: cloudEntry]) {
                    skipped++;
                    continue;
                }
                NSString *cloudHash = [self hashOfCloudFile: cloudURL];
                if (cloudHash && [cloudHash isEqualToString: base]) {      // deleted here, unchanged in iCloud
                    CloudLog(@"%@ was deleted here; deleting it in iCloud", subPath);
                    if ([self deleteCloudFile: cloudURL expecting: cloudHash]) {
                        [self setBaseHash: nil for: subPath];
                        deletions++;
                    }
                    continue;
                }
            }
            if (!localExists && ![fm createDirectoryAtPath: localDir withIntermediateDirectories: YES attributes: nil error: nil])
                continue;
            if (![self ensureDownloaded: cloudEntry]) {
                skipped++;
                continue;
            }
            CloudLog(@"downloading %@", subPath);
            NSString *downloaded = [self copyCloud: cloudURL toLocal: localPath replacing: nil]; // nothing was here when the pass began
            if (downloaded) {
                [self setBaseHash: downloaded for: subPath];
                changed = YES;
                downloads++;
                localExists = YES;
            }
        }
    }
    // Records for saves on neither side are dropped once a full pass has seen both listings. A
    // save removed on both sides outside Frotz is never visited above, so its record would outlive
    // it, and the same file restored here later (from a backup, say) would read as a deletion that
    // iCloud hadn't yet received, and be deleted.
    if (completed) {
        NSString *prefix = RecordKey([subFolder stringByAppendingString: @"/"]);
        NSMutableSet<NSString*> *seen = [NSMutableSet set];
        for (NSString *key in keys)
            [seen addObject: RecordKey([subFolder stringByAppendingPathComponent: key])];
        NSMutableDictionary *hashes = m_record[kRecordHashesKey];
        for (NSString *recordKey in [hashes allKeys])
            if ([recordKey hasPrefix: prefix] && ![seen containsObject: recordKey]) {
                CloudLog(@"%@ is gone from both sides; forgetting it", recordKey);
                [hashes removeObjectForKey: recordKey];
            }
    }
    [self saveRecord];
    CloudLog(@"%@: %lu here, %lu in iCloud; %d up, %d down, %d deleted, %d left for next time", subFolder,
             (unsigned long)[local count], (unsigned long)[cloud count], uploads, downloads, deletions, skipped);
    return changed;
}

// Noted at once, not queued: the caller recreates the folder right after this, and a pass already
// queued for it would otherwise run first, find the folder present and empty with the old
// records, and delete iCloud's saves. Passes apply pending forgets when they start and before
// each file (applyPendingForgets), so a running pass sees it too. The queued block only persists it.
- (void)forgetSaveFolder:(NSString*)subFolder {
    @synchronized (m_pendingForgets) {
        [m_pendingForgets addObject: subFolder];
    }
    dispatch_async(m_queue, ^{
        [self loadRecord];
        [self applyPendingForgets];
    });
}

// Queue only.
- (void)applyPendingForgets {
    NSSet<NSString*> *folders;
    @synchronized (m_pendingForgets) {
        if (![m_pendingForgets count])
            return;
        folders = [m_pendingForgets copy];
        [m_pendingForgets removeAllObjects];
    }
    for (NSString *folder in folders)
        [self forgetBasesForFolder: folder];
}

- (void)saveDeleted:(NSString*)subPath {
    if (!self.enabled)
        return;
    while ([subPath hasPrefix: @"/"])
        subPath = [subPath substringFromIndex: 1];
    dispatch_async(m_queue, ^{
        if (!self.enabled || ![self containerURL]) // the switch may have gone off while this waited
            return;
        [self loadRecord];
        NSURL *cloudURL = [[self cloudSavesURL] URLByAppendingPathComponent: subPath];
        BOOL exists = NO;
        NSDictionary *entries = [self cloudEntriesIn: [cloudURL URLByDeletingLastPathComponent] exists: &exists];
        // The record goes only once iCloud's copy is known to be gone. Forgetting it after a failed
        // listing or deletion left the surviving copy looking new, so the next sync downloaded it
        // and undid the deletion. Kept, the record lets that sync delete it instead: a save only in
        // iCloud, unchanged since the last sync, with its local copy gone.
        BOOL gone;
        NSString *base = [self baseHashFor: subPath];
        CloudSyncEntry *entry = entries[[subPath.lastPathComponent lowercaseString]];
        if (!entries)
            gone = !exists; // no folder in iCloud, nothing to delete; a folder that couldn't be listed is tried again next time
        else if (!entry)
            gone = YES;
        else if (!base) {
            // Never synced from here, so iCloud's file isn't the one just deleted: another device's
            // save that happens to share the name. It stays, and the next sync brings it down.
            CloudLog(@"%@ was deleted in Frotz, but iCloud's copy was never synced here; leaving it", subPath);
            return;
        } else {
            CloudLog(@"%@ was deleted in Frotz; deleting it in iCloud", subPath);
            // The entry's URL, not one built from the local name: the match ignores case, the file system doesn't.
            gone = [self deleteCloudFile: entry.url expecting: base]; // only if unchanged since the last sync; else it comes back down next time
        }
        if (gone) {
            [self setBaseHash: nil for: subPath];
            [self saveRecord];
        } else
            CloudLog(@"%@: iCloud's copy couldn't be removed yet; the next sync will", subPath);
    });
}

@end

#endif // EnableCloudSaveSync
