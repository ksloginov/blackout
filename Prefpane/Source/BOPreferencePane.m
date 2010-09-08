/*
 * Copyright (C) 2010 Michael Dippery <mdippery@gmail.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import "BOPreferencePane.h"

#import <CoreServices/CoreServices.h>

#import "BOBundle.h"
#import "BONotifications.h"
#import "BOKeys.h"


@interface BOPreferencePane ()
- (BOOL)shouldUpdateAutomatically;
- (LSSharedFileListItemRef) loginItem:(LSSharedFileListRef *)items;
- (void)updateRunningState:(BOOL)state;
- (void)updateKeyCombo;
- (void)updateLoginItemState;
- (void)disableControlsWithLabel:(NSString *)labelKey;
- (void)launchBlackout;
- (void)terminateBlackout;
- (void)checkBlackoutIsRunning;
- (void)checkedForUpdate:(NSNotification *)note;
@end


@implementation BOPreferencePane

@dynamic notificationIdentifier;

- (void)awakeFromNib
{
    NSDictionary *info = [[BOBundle preferencePaneBundle] infoDictionary];
    NSString *version = [NSString stringWithFormat:@"v%@ (%@)",
                            [info objectForKey:@"CFBundleShortVersionString"],
                            [info objectForKey:@"CFBundleVersion"]];
    NSString *copyright = NSLocalizedStringFromTableInBundle(
                              @"NSHumanReadableCopyright",
                              @"InfoPlist",
                              [BOBundle preferencePaneBundle],
                              nil);
    [versionLabel setStringValue:version];
    [copyrightLabel setStringValue:copyright];
    
    NSDistributedNotificationCenter *dnc = [NSDistributedNotificationCenter defaultCenter];
    [dnc addObserver:self selector:@selector(checkedForUpdate:) name:BOApplicationDidCheckForUpdate object:nil];
    
    [self updateRunningState:[self isBlackoutRunning]];
    [self updateKeyCombo];
    [self updateLoginItemState];    
    [updateCheckbox setState:[self shouldUpdateAutomatically]];
}

- (NSString *)notificationIdentifier
{
    return [[BOBundle preferencePaneBundle] bundleIdentifier];
}

- (BOOL)shouldUpdateAutomatically
{
    NSString *helperIdent = [[BOBundle helperBundle] bundleIdentifier];
    NSLog(@"Checking preferences for %@", helperIdent);
    CFBooleanRef userPref = CFPreferencesCopyAppValue(CFSTR("SUEnableAutomaticChecks"), (CFStringRef) helperIdent);
    if (userPref && CFBooleanGetValue(userPref)) {
        NSLog(@"Received user preference -- it's a yes!");
        CFRelease(userPref);
        return YES;
    } else {
        NSLog(@"Failed to get preferences for %@", helperIdent);
        if (userPref) CFRelease(userPref);
        NSDictionary *info = [[BOBundle helperBundle] infoDictionary];
        id appPref = [info objectForKey:@"SUEnableAutomaticChecks"];
        if (appPref) {
            NSLog(@"No matter, got value from app info dict");
            return [appPref boolValue];
        } else {
            NSLog(@"Hm, couldn't even get the info dict value");
            return NO;
        }
    }
}

- (LSSharedFileListItemRef)loginItem:(LSSharedFileListRef *)items
{
    // Source: http://cocoatutorial.grapewave.com/2010/02/creating-andor-removing-a-login-item/
    
    LSSharedFileListItemRef theItem = NULL;
    CFURLRef appPath = (CFURLRef) [NSURL fileURLWithPath:[self blackoutHelperPath]];
    LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    if (loginItems) {
        UInt32 seedValue;
        NSArray *loginItemsList = (NSArray *) LSSharedFileListCopySnapshot(loginItems, &seedValue);
        for (NSUInteger i = 0; i < [loginItemsList count]; i++) {
            LSSharedFileListItemRef item = (LSSharedFileListItemRef) [loginItemsList objectAtIndex:i];
            if (LSSharedFileListItemResolve(item, 0, (CFURLRef *) &appPath, NULL) == noErr) {
                if ([[(NSURL *) appPath path] isEqualToString:[self blackoutHelperPath]]) {
                    theItem = item;
                    break;
                }
            }
        }
        [loginItemsList release];
    }
    
    if (items) *items = loginItems;
    return theItem;
}

- (void)updateRunningState:(BOOL)state
{
    if (state) {
        [runningLabel setStringValue:NSLocalizedString(@"Blackout is running.", nil)];
        [startButton setTitle:NSLocalizedString(@"Stop Blackout", nil)];
        [startButton setAction:@selector(stopBlackout:)];
        [updateButton setEnabled:YES];
    } else {
        [runningLabel setStringValue:NSLocalizedString(@"Blackout is stopped.", nil)];
        [startButton setTitle:NSLocalizedString(@"Start Blackout", nil)];
        [startButton setAction:@selector(startBlackout:)];
        [updateButton setEnabled:NO];
    }
}

- (void)updateKeyCombo
{
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    NSInteger keys = [prefs integerForKey:BOKeyCodeNotificationKey];
    NSInteger mods = [prefs integerForKey:BOKeyFlagNotificationKey];
    
    if (keys == 0) keys = BODefaultKeyCode;
    if (mods == 0) mods = SRCarbonToCocoaFlags(BODefaultModifiers);
    
    KeyCombo keyCombo = SRMakeKeyCombo(keys, mods);
    [shortcutRecorder setKeyCombo:keyCombo];
}

- (void)updateLoginItemState
{
    LSSharedFileListItemRef item = [self loginItem:NULL];
    BOOL isLoginItem = !!item;
    [loginItemsCheckbox setState:isLoginItem];
    [loginItemsCheckbox setAction:isLoginItem ? @selector(removeFromLoginItems:) : @selector(addToLoginItems:)];
}

- (NSString *)blackoutHelperPath
{
    return [[BOBundle preferencePaneBundle] pathForResource:@"Blackout" ofType:@"app"];
}

- (BOOL)isBlackoutRunning
{
    ProcessSerialNumber psn = {0, kNoProcess };
    
    while (GetNextProcess(&psn) == noErr) {
        NSDictionary *info = [NSMakeCollectable(ProcessInformationCopyDictionary(&psn, kProcessDictionaryIncludeAllInformationMask)) autorelease];
        if (info) {
            NSString *bundlePath = [info objectForKey:@"BundlePath"];
            NSString *bundleID = [info objectForKey:(NSString *) kCFBundleIdentifierKey];
            if (bundlePath && bundleID) {
                if ([bundleID isEqualToString:@"com.monkey-robot.Blackout"]) {
                    return YES;
                }
            }
        }
    }
    
    return NO;
}

- (void)disableControlsWithLabel:(NSString *)labelKey
{
    [startButton setEnabled:NO];
    [launchIndicator startAnimation:self];
    [runningLabel setStringValue:NSLocalizedString(labelKey, nil)];
}

- (IBAction)startBlackout:(id)sender
{
    [self disableControlsWithLabel:NSLocalizedString(@"Launching Blackout...", nil)];
    [self launchBlackout];
    [self performSelector:@selector(checkBlackoutIsRunning) withObject:nil afterDelay:4.0];
}

- (IBAction)stopBlackout:(id)sender
{
    [self disableControlsWithLabel:NSLocalizedString(@"Stopping Blackout...", nil)];
    [self terminateBlackout];
    [self performSelector:@selector(checkBlackoutIsRunning) withObject:nil afterDelay:4.0];
}

- (void)launchBlackout
{
    static NSWorkspaceLaunchOptions opts = NSWorkspaceLaunchWithoutAddingToRecents | NSWorkspaceLaunchWithoutActivation | NSWorkspaceLaunchAsync;
    NSURL *url = [NSURL fileURLWithPath:[self blackoutHelperPath]];
    [[NSWorkspace sharedWorkspace] openURLs:[NSArray arrayWithObject:url]
                    withAppBundleIdentifier:nil
                                    options:opts
             additionalEventParamDescriptor:nil
                          launchIdentifiers:NULL];
}

- (void)terminateBlackout
{
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:BOApplicationShouldTerminate object:[self notificationIdentifier]];
}

- (void)checkBlackoutIsRunning
{
    [self updateRunningState:[self isBlackoutRunning]];
    [launchIndicator stopAnimation:self];
    [startButton setEnabled:YES];
}

#pragma mark Interface

- (IBAction)addToLoginItems:(id)sender
{
    // Source: http://cocoatutorial.grapewave.com/2010/02/creating-andor-removing-a-login-item/
    
    CFURLRef appPath = (CFURLRef) [NSURL fileURLWithPath:[self blackoutHelperPath]];
    LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    if (loginItems) {
        LSSharedFileListItemRef item = LSSharedFileListInsertItemURL(loginItems, kLSSharedFileListItemLast, NULL, NULL, appPath, NULL, NULL);
        NSLog(@"Added Blackout to login items");
        if (item) CFRelease(item);
    }
    
    [loginItemsCheckbox setAction:@selector(removeFromLoginItems:)];
}

- (IBAction)removeFromLoginItems:(id)sender
{
    LSSharedFileListRef loginItems;
    LSSharedFileListItemRef item = [self loginItem:&loginItems];
    if (item) {
        LSSharedFileListItemRemove(loginItems, item);
    }
    [loginItemsCheckbox setAction:@selector(addToLoginItems:)];
}

- (IBAction)checkForUpdate:(id)sender
{
    NSLog(@"Checking for updates");
    [updateButton setEnabled:NO];
    [updateIndicator startAnimation:self];
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:BOApplicationShouldCheckForUpdate
                                                                   object:[self notificationIdentifier]];
}

#pragma mark Shortcut Recorder

- (void)shortcutRecorder:(SRRecorderControl *)recorder keyComboDidChange:(KeyCombo)newKeyCombo
{
    NSNumber *code = [NSNumber numberWithUnsignedShort:newKeyCombo.code];
    NSNumber *flags = [NSNumber numberWithUnsignedInteger:SRCocoaToCarbonFlags(newKeyCombo.flags)];
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
                             code, BOKeyCodeNotificationKey,
                             flags, BOKeyFlagNotificationKey,
                             nil];
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:BOApplicationShouldUpdateHotkeys
                                                                   object:[self notificationIdentifier]
                                                                 userInfo:info];
}

#pragma mark Notifications

- (void)checkedForUpdate:(NSNotification *)note
{
    [updateIndicator stopAnimation:self];
    [updateButton setEnabled:YES];
    NSLog(@"Checked for updates");
}

@end
