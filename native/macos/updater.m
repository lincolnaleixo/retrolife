#import <Cocoa/Cocoa.h>
#import <Security/Security.h>
#import <Sparkle/Sparkle.h>
#include <stdlib.h>
#include <string.h>
#import "updater.h"

#ifdef RETROLIFE_UPDATER_TESTING
static NSString *const RLBundleID = @"io.github.lincolnaleixo.retrolife.updater-test";
#else
static NSString *const RLBundleID = @"io.github.lincolnaleixo.retrolife";
#endif
static NSString *const RLFeedURL = @"https://raw.githubusercontent.com/lincolnaleixo/retrolife/updates/appcast.xml";
static NSString *const RLBetaKey = @"RLIncludeBetaUpdates";

#ifdef RETROLIFE_UPDATER_TESTING
/* Only the test executable supplies this. Never compiled into the release dylib. */
extern id<SPUUserDriver> rl_test_user_driver(void);
#endif

@interface RLUpdater : NSObject <SPUUpdaterDelegate, NSMenuItemValidation>
@property(nonatomic, strong) SPUStandardUpdaterController *controller;
@property(nonatomic, strong) SPUUpdater *updater;
@property(nonatomic, strong) NSMenuItem *menuItem;
@property(nonatomic, copy) NSString *state;
@property(nonatomic, copy) NSString *message;
@property(nonatomic, copy) NSString *availableVersion;
@property(nonatomic) BOOL available;
@property(nonatomic) BOOL gameActive;
@property(nonatomic) BOOL installPending;
@property(nonatomic, copy) void (^resumeInstallation)(void);
- (NSDictionary *)perform:(NSString *)command;
@end

static BOOL RLTrustedHost(NSBundle *bundle) {
    SecStaticCodeRef code = NULL;
    CFDictionaryRef information = NULL;
    BOOL trusted = NO;
    if (SecStaticCodeCreateWithPath((__bridge CFURLRef)bundle.bundleURL, kSecCSDefaultFlags, &code) == errSecSuccess) {
        if (SecStaticCodeCheckValidity(code, kSecCSStrictValidate, NULL) == errSecSuccess &&
            SecCodeCopySigningInformation(code, kSecCSSigningInformation, &information) == errSecSuccess) {
            NSDictionary *details = (__bridge NSDictionary *)information;
            trusted = [details[(__bridge NSString *)kSecCodeInfoTeamIdentifier] length] > 0;
        }
    }
    if (information) CFRelease(information);
    if (code) CFRelease(code);
    return trusted;
}

static BOOL RLAllowedDownload(NSURL *url) {
#ifdef RETROLIFE_UPDATER_TESTING
    if ([url.scheme isEqualToString:@"http"] && [url.host isEqualToString:@"127.0.0.1"]) return YES;
#endif
    return [url.scheme isEqualToString:@"https"] && [url.host isEqualToString:@"github.com"] &&
        !url.user && !url.password && !url.port && !url.query && !url.fragment &&
        [url.path hasPrefix:@"/lincolnaleixo/retrolife/releases/download/v"] &&
        [url.lastPathComponent isEqualToString:@"RetroLife-macos-arm64.zip"];
}

@implementation RLUpdater
- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    self.state = @"unavailable";
    self.message = @"Updates are available in installed, signed macOS releases. This build is not update-enabled.";
    self.availableVersion = @"";
    NSBundle *bundle = NSBundle.mainBundle;
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--headless"]) return self;
    NSString *feed = [bundle objectForInfoDictionaryKey:@"SUFeedURL"];
    NSString *key = [bundle objectForInfoDictionaryKey:@"SUPublicEDKey"];
    NSData *decoded = [key isKindOfClass:NSString.class] ? [[NSData alloc] initWithBase64EncodedString:key options:0] : nil;
    BOOL validFeed = [feed isEqualToString:RLFeedURL];
    BOOL trusted = RLTrustedHost(bundle);
#ifdef RETROLIFE_UPDATER_TESTING
    validFeed = [feed hasPrefix:@"http://127.0.0.1:"];
    trusted = YES;
#endif
    if (![bundle.bundleIdentifier isEqualToString:RLBundleID] || !validFeed || decoded.length != 32 || !trusted) return self;
    NSNumber *readOnly = nil;
    [bundle.bundleURL getResourceValue:&readOnly forKey:NSURLVolumeIsReadOnlyKey error:NULL];
    if (readOnly.boolValue || [bundle.bundlePath.pathComponents containsObject:@"AppTranslocation"]) {
        self.message = @"Move RetroLife to Applications and open it there before checking for updates.";
        return self;
    }
    if (![NSUserDefaults.standardUserDefaults objectForKey:RLBetaKey]) {
        [NSUserDefaults.standardUserDefaults setBool:[[bundle objectForInfoDictionaryKey:@"RLDefaultBetaUpdates"] boolValue] forKey:RLBetaKey];
    }
#ifdef RETROLIFE_UPDATER_TESTING
    self.updater = [[SPUUpdater alloc] initWithHostBundle:bundle applicationBundle:bundle userDriver:rl_test_user_driver() delegate:self];
#else
    self.controller = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:NO updaterDelegate:self userDriverDelegate:nil];
    self.updater = self.controller.updater;
#endif
    NSError *error = nil;
    if (![self.updater startUpdater:&error]) {
        self.message = @"The updater could not start. Check the release configuration.";
        return self;
    }
    self.available = YES;
    self.state = @"idle";
    self.message = @"Ready to check for updates.";
    [self addMenuItem];
    return self;
}

- (void)addMenuItem {
    NSMenu *menu = NSApp.mainMenu.itemArray.firstObject.submenu;
    if (!menu || self.menuItem) return;
    self.menuItem = [[NSMenuItem alloc] initWithTitle:@"Check for Updates..." action:@selector(checkFromMenu:) keyEquivalent:@""];
    self.menuItem.target = self;
    [menu insertItem:self.menuItem atIndex:MIN((NSInteger)2, menu.numberOfItems)];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    return self.available && !self.gameActive && self.updater.canCheckForUpdates;
}

- (void)checkFromMenu:(id)sender {
    [self perform:@"check"];
}

- (NSDictionary *)response:(NSString *)error {
    NSBundle *bundle = NSBundle.mainBundle;
    NSDictionary *data = @{
        @"available": @(self.available), @"state": self.state ?: @"unavailable",
        @"message": self.message ?: @"", @"currentVersion": [bundle objectForInfoDictionaryKey:@"RLReleaseVersion"] ?: @"Development build",
        @"availableVersion": self.availableVersion ?: @"",
        @"canCheck": @(self.available && !self.gameActive && self.updater.canCheckForUpdates),
        @"automaticChecks": @(self.updater.automaticallyChecksForUpdates),
        @"automaticDownloads": @(self.updater.automaticallyDownloadsUpdates),
        @"includeBeta": @([NSUserDefaults.standardUserDefaults boolForKey:RLBetaKey]),
        @"sessionInProgress": @(self.updater.sessionInProgress),
        @"gameActive": @(self.gameActive), @"installPending": @(self.installPending),
        @"lastChecked": @(self.updater.lastUpdateCheckDate.timeIntervalSince1970),
    };
    if (error) return @{@"schemaVersion": @1, @"ok": @NO, @"error": error, @"data": data};
    return @{@"schemaVersion": @1, @"ok": @YES, @"data": data};
}

- (NSDictionary *)perform:(NSString *)command {
    if ([command isEqualToString:@"status"]) {
        [self addMenuItem];
        return [self response:nil];
    }
    // These two commands are internal to the Rust emulation boundary, not UI APIs.
    if ([command isEqualToString:@"game_begin"]) {
        if (self.gameActive || self.updater.sessionInProgress || self.installPending) {
            return [self response:@"Finish or cancel the pending update before starting a game."];
        }
        self.gameActive = YES;
        return [self response:nil];
    }
    if ([command isEqualToString:@"game_end"]) {
        self.gameActive = NO;
        if (self.resumeInstallation) {
            void (^resume)(void) = self.resumeInstallation;
            self.resumeInstallation = nil;
            dispatch_async(dispatch_get_main_queue(), resume);
        }
        return [self response:nil];
    }
    if (!self.available) return [self response:self.message];
    if (self.gameActive) return [self response:@"Return to the library after saving before managing updates."];
    if ([command isEqualToString:@"check"]) {
        if (!self.updater.canCheckForUpdates) return [self response:@"An update check or installation is already in progress."];
        self.state = @"checking";
        self.message = @"Checking for updates...";
        [self.updater checkForUpdates];
        return [self response:nil];
    }
    if (self.updater.sessionInProgress || self.installPending) return [self response:@"Finish or cancel the current update before changing update settings."];
    if ([command isEqualToString:@"checks_on"]) self.updater.automaticallyChecksForUpdates = YES;
    else if ([command isEqualToString:@"checks_off"]) {
        self.updater.automaticallyDownloadsUpdates = NO;
        self.updater.automaticallyChecksForUpdates = NO;
    } else if ([command isEqualToString:@"downloads_on"]) {
        self.updater.automaticallyChecksForUpdates = YES;
        self.updater.automaticallyDownloadsUpdates = YES;
    } else if ([command isEqualToString:@"downloads_off"]) self.updater.automaticallyDownloadsUpdates = NO;
    else if ([command isEqualToString:@"beta_on"] || [command isEqualToString:@"beta_off"]) {
        [NSUserDefaults.standardUserDefaults setBool:[command isEqualToString:@"beta_on"] forKey:RLBetaKey];
        [self.updater resetUpdateCycle];
    } else return [self response:@"Unknown updater command."];
    return [self response:nil];
}

- (BOOL)updater:(SPUUpdater *)updater mayPerformUpdateCheck:(SPUUpdateCheck)check error:(NSError **)error {
    if (!self.gameActive) return YES;
    if (error) *error = [NSError errorWithDomain:@"RetroLifeUpdates" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Updates are deferred while a game is active or saving."}];
    return NO;
}

- (NSSet<NSString *> *)allowedChannelsForUpdater:(SPUUpdater *)updater {
    return [NSUserDefaults.standardUserDefaults boolForKey:RLBetaKey] ? [NSSet setWithObject:@"beta"] : [NSSet set];
}

- (BOOL)updater:(SPUUpdater *)updater shouldProceedWithUpdate:(SUAppcastItem *)item updateCheck:(SPUUpdateCheck)check error:(NSError **)error {
    NSDictionary *enclosure = item.propertiesDictionary[@"enclosure"];
    NSString *signature = [enclosure isKindOfClass:NSDictionary.class] ? enclosure[@"sparkle:edSignature"] : nil;
    NSData *decoded = [signature isKindOfClass:NSString.class] ? [[NSData alloc] initWithBase64EncodedString:signature options:0] : nil;
    if (!self.gameActive && RLAllowedDownload(item.fileURL) && decoded.length == 64) return YES;
    if (error) *error = [NSError errorWithDomain:@"RetroLifeUpdates" code:2 userInfo:@{NSLocalizedDescriptionKey: @"This update is not an allowed signed RetroLife package, or gameplay is still active."}];
    return NO;
}

- (BOOL)updater:(SPUUpdater *)updater shouldDownloadReleaseNotesForUpdate:(SUAppcastItem *)item { return NO; }

- (void)updater:(SPUUpdater *)updater didFindValidUpdate:(SUAppcastItem *)item {
    self.availableVersion = item.displayVersionString;
    self.state = @"available";
    self.message = [NSString stringWithFormat:@"RetroLife %@ is available.", item.displayVersionString];
}

- (void)updaterDidNotFindUpdate:(SPUUpdater *)updater error:(NSError *)error {
    self.state = @"up_to_date";
    self.availableVersion = @"";
    self.message = @"No newer compatible update is available on the selected channel.";
}

- (void)updater:(SPUUpdater *)updater willDownloadUpdate:(SUAppcastItem *)item withRequest:(NSMutableURLRequest *)request {
    self.state = @"downloading";
    self.message = @"Downloading the update. Your library and saves will not be changed.";
}

- (void)updater:(SPUUpdater *)updater willExtractUpdate:(SUAppcastItem *)item {
    self.state = @"verifying";
    self.message = @"Verifying and preparing the signed update...";
}

- (void)updater:(SPUUpdater *)updater willInstallUpdate:(SUAppcastItem *)item {
    self.installPending = YES;
    self.state = @"installing";
    self.message = @"Installing the verified update...";
}

- (BOOL)updater:(SPUUpdater *)updater shouldPostponeRelaunchForUpdate:(SUAppcastItem *)item untilInvokingBlock:(void (^)(void))handler {
    if (!self.gameActive) return NO;
    self.installPending = YES;
    self.resumeInstallation = handler;
    self.state = @"deferred";
    self.message = @"Update ready. Waiting for the game to finish saving.";
    return YES;
}

- (BOOL)updaterShouldRelaunchApplication:(SPUUpdater *)updater { return !self.gameActive; }

- (void)updater:(SPUUpdater *)updater didAbortWithError:(NSError *)error {
    if (error.code == SUNoUpdateError && [error.domain isEqualToString:SUSparkleErrorDomain]) return;
    self.installPending = NO;
    self.resumeInstallation = nil;
    self.state = @"error";
    self.message = @"The update could not be completed. Your current app and saves have been kept. Please retry.";
}

- (void)updater:(SPUUpdater *)updater didFinishUpdateCycleForUpdateCheck:(SPUUpdateCheck)check error:(NSError *)error {
    if (!error && [self.state isEqualToString:@"checking"]) {
        self.state = @"idle";
        self.message = @"Update check finished.";
    }
}
@end

char *rl_updater_command(const char *command) {
    @autoreleasepool {
        if (![NSThread isMainThread] || !command) {
            return strdup("{\"schemaVersion\":1,\"ok\":false,\"error\":\"Updater calls require the main thread.\"}");
        }
        static RLUpdater *manager;
        if (!manager) manager = [RLUpdater new];
        NSString *value = [NSString stringWithUTF8String:command];
        NSDictionary *response = [manager perform:value ?: @""];
        NSData *json = [NSJSONSerialization dataWithJSONObject:response options:0 error:NULL];
        NSString *encoded = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
        return strdup(encoded.UTF8String ?: "{\"schemaVersion\":1,\"ok\":false,\"error\":\"Updater response unavailable.\"}");
    }
}
void rl_updater_free(char *value) { free(value); }
