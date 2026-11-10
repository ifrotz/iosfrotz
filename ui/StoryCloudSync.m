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
}

- (instancetype)initWithLocalSavesPath:(NSString*)savesPath {
    if ((self = [super init])) {
        m_savesPath = [savesPath copy];
        m_queue = dispatch_queue_create("com.flippencorp.frotz.cloudsync", DISPATCH_QUEUE_SERIAL);
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
- (void)loadRecord {
    if (!m_record)
        m_record = [NSMutableDictionary dictionaryWithContentsOfFile: [self recordPath]] ?: [NSMutableDictionary dictionary];
    id<NSObject,NSCopying,NSCoding> token = [[NSFileManager defaultManager] ubiquityIdentityToken];
    NSData *identity = token ? [NSKeyedArchiver archivedDataWithRootObject: token requiringSecureCoding: NO error: nil] : nil;
    NSData *recorded = m_record[kRecordIdentityKey];
    if (identity && recorded && ![identity isEqualToData: recorded]) {
        CloudLog(@"iCloud account changed; forgetting what was synced for the previous one");
        [m_record removeObjectForKey: kRecordHashesKey];
    }
    if (identity)
        m_record[kRecordIdentityKey] = identity;
    if (![m_record[kRecordHashesKey] isKindOfClass: [NSMutableDictionary class]])
        m_record[kRecordHashesKey] = m_record[kRecordHashesKey] ? [m_record[kRecordHashesKey] mutableCopy] : [NSMutableDictionary dictionary];
}

- (void)saveRecord {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList: m_record format: NSPropertyListBinaryFormat_v1_0 options: 0 error: nil];
    if (data)
        [data writeToFile: [self recordPath] atomically: YES];
}

- (NSString*)baseHashFor:(NSString*)subPath {
    return m_record[kRecordHashesKey][subPath];
}

- (void)setBaseHash:(NSString*)hash for:(NSString*)subPath {
    if (hash)
        m_record[kRecordHashesKey][subPath] = hash;
    else
        [m_record[kRecordHashesKey] removeObjectForKey: subPath];
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
    while ([deadline timeIntervalSinceNow] > 0) {
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

- (BOOL)copyLocal:(NSString*)localPath toCloud:(NSURL*)cloudURL {
    NSFileManager *fm = [NSFileManager defaultManager];
    __block BOOL ok = NO;
    NSError *coordError = nil;
    [[[NSFileCoordinator alloc] initWithFilePresenter: nil] coordinateWritingItemAtURL: cloudURL options: NSFileCoordinatorWritingForReplacing error: &coordError byAccessor: ^(NSURL *writeURL) {
        NSError *error = nil;
        [fm removeItemAtURL: writeURL error: nil];
        ok = [fm copyItemAtURL: [NSURL fileURLWithPath: localPath] toURL: writeURL error: &error];
        if (!ok)
            CloudLog(@"upload of %@ failed: %@", localPath.lastPathComponent, error);
    }];
    if (coordError)
        CloudLog(@"upload of %@ failed: %@", localPath.lastPathComponent, coordError);
    return ok;
}

- (BOOL)copyCloud:(NSURL*)cloudURL toLocal:(NSString*)localPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    __block BOOL ok = NO;
    NSError *coordError = nil;
    [[[NSFileCoordinator alloc] initWithFilePresenter: nil] coordinateReadingItemAtURL: cloudURL options: NSFileCoordinatorReadingWithoutChanges error: &coordError byAccessor: ^(NSURL *readURL) {
        NSError *error = nil;
        NSString *tmp = [localPath stringByAppendingString: @".icloud-download"];
        [fm removeItemAtPath: tmp error: nil];
        if ([fm copyItemAtURL: readURL toURL: [NSURL fileURLWithPath: tmp] error: &error]) {
            [fm removeItemAtPath: localPath error: nil];
            ok = [fm moveItemAtPath: tmp toPath: localPath error: &error];
        }
        if (!ok) {
            [fm removeItemAtPath: tmp error: nil];
            CloudLog(@"download of %@ failed: %@", cloudURL.lastPathComponent, error);
        }
    }];
    if (coordError)
        CloudLog(@"download of %@ failed: %@", cloudURL.lastPathComponent, coordError);
    return ok;
}

- (BOOL)deleteCloudFile:(NSURL*)cloudURL {
    NSFileManager *fm = [NSFileManager defaultManager];
    __block BOOL ok = NO;
    NSError *coordError = nil;
    [[[NSFileCoordinator alloc] initWithFilePresenter: nil] coordinateWritingItemAtURL: cloudURL options: NSFileCoordinatorWritingForDeleting error: &coordError byAccessor: ^(NSURL *writeURL) {
        NSError *error = nil;
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

// "name (conflict 2026-11-09).ext", or with a counter if that exists too, in `dir`.
static NSString *UniqueConflictPath(NSString *dir, NSString *name) {
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
        if (![fm fileExistsAtPath: path])
            return path;
    }
    return nil;
}

// iCloud's own conflicts: two devices wrote the same mirror file before either saw the other's
// version. Each extra version becomes a local "(conflict date)" save, unless its content is
// already here, and the versions are then resolved so iCloud stops tracking them. The new local
// files are uploaded by the main pass, as local-only saves with no base.
- (BOOL)absorbConflictVersionsOf:(CloudSyncEntry*)entry intoLocalDir:(NSString*)localDir knownHashes:(NSSet<NSString*>*)knownHashes {
    NSArray<NSFileVersion*> *versions = [NSFileVersion unresolvedConflictVersionsOfItemAtURL: entry.url];
    if (![versions count])
        return NO;
    BOOL changed = NO;
    for (NSFileVersion *version in versions) {
        NSString *hash = version.URL ? FrotzFileContentHash(version.URL.path) : nil;
        if (hash && ![knownHashes containsObject: hash]) {
            NSString *dest = UniqueConflictPath(localDir, entry.name);
            if (dest && [[NSFileManager defaultManager] copyItemAtPath: version.URL.path toPath: dest error: nil]) {
                CloudLog(@"%@ was changed on two devices at once; the other version is kept as %@", entry.name, dest.lastPathComponent);
                changed = YES;
            }
        }
        version.resolved = YES;
    }
    [NSFileVersion removeOtherVersionsOfItemAtURL: entry.url error: nil];
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
    if (![self containerURL]) {
        CloudLog(@"iCloud Drive isn't available; not syncing %@", subFolder);
        return NO;
    }
    [self loadRecord];

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
    if (!localExists)
        CloudLog(@"no local folder at %@; taking what iCloud has", localDir);

    // The iCloud side. Created if missing: a missing folder means never synced, so everything
    // local is uploaded and nothing is deleted.
    BOOL cloudExisted = NO;
    NSDictionary<NSString*,CloudSyncEntry*> *cloud = [self cloudEntriesIn: cloudDir exists: &cloudExisted];
    if (!cloud) {
        if (cloudExisted)
            return NO; // listing failed; try again next time
        if (![fm createDirectoryAtURL: cloudDir withIntermediateDirectories: YES attributes: nil error: &error]) {
            CloudLog(@"can't create %@ in iCloud: %@", subFolder, error);
            return NO;
        }
        CloudLog(@"created %@ in iCloud", subFolder);
        cloud = @{};
    }

    // Fold in any versions iCloud is holding as conflicts, then list local files afresh.
    NSMutableSet<NSString*> *localHashes = [NSMutableSet set];
    NSMutableDictionary<NSString*,NSString*> *localHashByName = [NSMutableDictionary dictionary];
    for (NSString *name in localNames) {
        if (!IsSyncableSaveName(name))
            continue;
        NSString *hash = FrotzFileContentHash([localDir stringByAppendingPathComponent: name]);
        if (hash) {
            localHashByName[[name lowercaseString]] = hash;
            [localHashes addObject: hash];
        }
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
    for (NSString *key in orderedKeys) {
        NSString *localName = local[key];
        CloudSyncEntry *cloudEntry = cloud[key];
        NSString *name = localName ?: cloudEntry.name;
        NSString *subPath = [subFolder stringByAppendingPathComponent: name];
        NSString *localPath = localName ? [localDir stringByAppendingPathComponent: localName] : [localDir stringByAppendingPathComponent: name];
        NSURL *cloudURL = cloudEntry ? cloudEntry.url : [cloudDir URLByAppendingPathComponent: name];
        NSString *base = [self baseHashFor: subPath];

        if (localName && cloudEntry) {
            if (![self ensureDownloaded: cloudEntry]) {
                skipped++;
                continue;
            }
            NSString *localHash = localHashByName[key] ?: FrotzFileContentHash(localPath);
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
                if ([self copyCloud: cloudURL toLocal: localPath]) {
                    [self setBaseHash: cloudHash for: subPath];
                    changed = YES;
                    downloads++;
                }
            } else if (base && [cloudHash isEqualToString: base]) {       // changed here only
                CloudLog(@"uploading %@", subPath);
                if ([self copyLocal: localPath toCloud: cloudURL]) {
                    [self setBaseHash: localHash for: subPath];
                    uploads++;
                }
            } else {                                                       // both, or no record: keep both
                NSString *conflictPath = UniqueConflictPath(localDir, localName);
                if (conflictPath && [fm moveItemAtPath: localPath toPath: conflictPath error: nil]) {
                    CloudLog(@"%@ differs here and in iCloud; local version kept as %@", subPath, conflictPath.lastPathComponent);
                    NSString *conflictSub = [subFolder stringByAppendingPathComponent: conflictPath.lastPathComponent];
                    if ([self copyLocal: conflictPath toCloud: [cloudDir URLByAppendingPathComponent: conflictPath.lastPathComponent]]) {
                        [self setBaseHash: localHash for: conflictSub];
                        uploads++;
                    }
                    if ([self copyCloud: cloudURL toLocal: localPath]) {
                        [self setBaseHash: cloudHash for: subPath];
                        downloads++;
                    }
                    changed = YES;
                } else
                    CloudLog(@"%@ differs here and in iCloud, but the local version couldn't be set aside; leaving both", subPath);
            }
        } else if (localName) {                                            // here, not in iCloud
            NSString *localHash = localHashByName[key] ?: FrotzFileContentHash(localPath);
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
                if ([self copyLocal: localPath toCloud: cloudURL]) {
                    [self setBaseHash: localHash for: subPath];
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
                    if ([self deleteCloudFile: cloudURL]) {
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
            if ([self copyCloud: cloudURL toLocal: localPath]) {
                [self setBaseHash: [self hashOfCloudFile: cloudURL] for: subPath];
                changed = YES;
                downloads++;
                localExists = YES;
            }
        }
    }
    [self saveRecord];
    CloudLog(@"%@: %lu here, %lu in iCloud; %d up, %d down, %d deleted, %d left for next time", subFolder,
             (unsigned long)[local count], (unsigned long)[cloud count], uploads, downloads, deletions, skipped);
    return changed;
}

- (void)saveDeleted:(NSString*)subPath {
    if (!self.enabled)
        return;
    while ([subPath hasPrefix: @"/"])
        subPath = [subPath substringFromIndex: 1];
    dispatch_async(m_queue, ^{
        if (![self containerURL])
            return;
        [self loadRecord];
        NSURL *cloudURL = [[self cloudSavesURL] URLByAppendingPathComponent: subPath];
        BOOL exists = NO;
        NSDictionary *entries = [self cloudEntriesIn: [cloudURL URLByDeletingLastPathComponent] exists: &exists];
        if (entries[[subPath.lastPathComponent lowercaseString]]) {
            CloudLog(@"%@ was deleted in Frotz; deleting it in iCloud", subPath);
            [self deleteCloudFile: cloudURL];
        }
        [self setBaseHash: nil for: subPath];
        [self saveRecord];
    });
}

@end

#endif // EnableCloudSaveSync
