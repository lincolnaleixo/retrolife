// Automated UI responses around the real Sparkle download/verification/installer.
// This executable, its test-only trust exception and keys are never shipped.
#import <Cocoa/Cocoa.h>
#import <Sparkle/Sparkle.h>
#import "updater.h"

static NSString *Mode(void) { return [NSBundle.mainBundle objectForInfoDictionaryKey:@"RLTestMode"]; }
static NSString *Directory(void) { return [NSBundle.mainBundle objectForInfoDictionaryKey:@"RLTestDirectory"]; }
static NSDictionary *Command(const char *name) {
    char *text = rl_updater_command(name);
    NSData *data = [NSData dataWithBytes:text length:strlen(text)];
    rl_updater_free(text);
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
}
static void Finish(BOOL passed, NSString *detail) {
    NSDictionary *value = @{@"passed": @(passed), @"mode": Mode(), @"detail": detail};
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingPrettyPrinted error:NULL];
    [data writeToFile:[Directory() stringByAppendingPathComponent:@"result.json"] atomically:YES];
    exit(passed ? 0 : 1);
}
static BOOL HasSignatureError(NSError *error) {
    if ([error.domain isEqualToString:SUSparkleErrorDomain] && (error.code == SUSignatureError || error.code == SUValidationError)) return YES;
    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    return underlying && underlying != error && HasSignatureError(underlying);
}

@interface SmokeDriver : NSObject <SPUUserDriver>
@end
@implementation SmokeDriver
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply {
    reply([[SUUpdatePermissionResponse alloc] initWithAutomaticUpdateChecks:NO sendSystemProfile:NO]);
}
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))cancellation {}
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)item state:(SPUUserUpdateState *)state reply:(void (^)(SPUUserUpdateChoice))reply {
    if ([Command("game_begin")[@"ok"] boolValue]) Finish(NO, @"Gameplay was allowed during an update session");
    if ([Mode() isEqualToString:@"no-update"] || [Mode() isEqualToString:@"downgrade"] || [Mode() isEqualToString:@"stable-only"]) Finish(NO, @"Unexpected update candidate");
    reply(SPUUserUpdateChoiceInstall);
}
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)data {}
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error {}
- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement {
    acknowledgement();
    BOOL expected = [@[@"no-update", @"downgrade", @"stable-only", @"incompatible-os"] containsObject:Mode()];
    Finish(expected, @"No newer compatible update offered");
}
- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement {
    acknowledgement();
    BOOL passed = ([Mode() isEqualToString:@"invalid-signature"] && HasSignatureError(error)) ||
                  ([Mode() isEqualToString:@"network-error"] && [error.domain isEqualToString:SUSparkleErrorDomain] && error.code == SUAppcastError) ||
                  ([Mode() isEqualToString:@"bad-origin"] && [error.domain isEqualToString:@"RetroLifeUpdates"]);
    Finish(passed, [NSString stringWithFormat:@"Update refused with %@ / %ld", error.domain, (long)error.code]);
}
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancellation {}
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)length {}
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length {}
- (void)showDownloadDidStartExtractingUpdate {}
- (void)showExtractionReceivedProgress:(double)progress {}
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))reply { reply(SPUUserUpdateChoiceInstall); }
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)terminated retryTerminatingApplication:(void (^)(void))retry {}
- (void)showUpdateInstalledAndRelaunched:(BOOL)relaunched acknowledgement:(void (^)(void))acknowledgement { acknowledgement(); }
- (void)dismissUpdateInstallation {}
@end
id<SPUUserDriver> rl_test_user_driver(void) { return [SmokeDriver new]; }

@interface SmokeApp : NSObject <NSApplicationDelegate>
@end
@implementation SmokeApp
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender { return NSTerminateNow; }
@end

static void RunScenario(void) {
    NSDictionary *status = Command("status");
    if (![status[@"data"][@"available"] boolValue]) Finish(NO, @"Native updater did not initialize");
    if (![status[@"data"][@"canCheck"] boolValue]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 20), dispatch_get_main_queue(), ^{ RunScenario(); });
        return;
    }
    if (![Command("game_begin")[@"ok"] boolValue]) Finish(NO, @"Game guard could not be acquired");
    if ([Command("check")[@"ok"] boolValue] || [Command("downloads_on")[@"ok"] boolValue]) Finish(NO, @"Update was allowed during gameplay");
    if (![Command("status")[@"data"][@"gameActive"] boolValue]) Finish(NO, @"Game guard was lost");
    if (![Command("game_end")[@"ok"] boolValue]) Finish(NO, @"Game guard was not released");
    if ([Mode() isEqualToString:@"policy"]) {
        if (![Command("downloads_on")[@"data"][@"automaticDownloads"] boolValue]) Finish(NO, @"Automatic downloads setting was not applied");
        if ([Command("checks_off")[@"data"][@"automaticDownloads"] boolValue]) Finish(NO, @"Disabling checks did not disable automatic downloads");
        if (![Command("beta_on")[@"data"][@"includeBeta"] boolValue] || [Command("beta_off")[@"data"][@"includeBeta"] boolValue]) Finish(NO, @"Beta preference did not round trip");
    }
    if ([Mode() isEqualToString:@"policy"]) Finish(YES, @"Settings, beta channel and gameplay barrier passed");
    if (![Command("check")[@"ok"] boolValue]) Finish(NO, @"Check for Updates could not begin");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        SmokeApp *delegate = [SmokeApp new];
        NSApp.delegate = delegate;
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        if ([Mode() isEqualToString:@"relaunched"]) Finish(YES, @"Real Sparkle installation replaced the bundle and relaunched the newer app");
        [NSUserDefaults.standardUserDefaults removePersistentDomainForName:NSBundle.mainBundle.bundleIdentifier];
        Command("status"); // Sparkle completes startup asynchronously on the main loop.
        dispatch_async(dispatch_get_main_queue(), ^{ RunScenario(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ Finish(NO, @"Native updater timed out"); });
        [NSApp run];
    }
    return 0;
}
