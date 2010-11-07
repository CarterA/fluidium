//  Copyright 2009 Todd Ditchendorf
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

#import "CRTwitterPlugIn.h"
#import "CRTwitterPlugInViewController.h"
#import "CRTimelineViewController.h"
#import "CRTwitterPlugInPrefsViewController.h"
#import "CRTwitterUtils.h"
#import <WebKit/WebKit.h>
#import <Fluidium/FUPlugInAPI.h>

NSString *kCRTwitterDisplayUsernamesKey = @"CRTwitterDisplayUsernames";
NSString *kCRTwitterAccountIDsKey = @"CRTwitterAccountIDs";
NSString *kCRTwitterSelectNewTabsAndWindowsKey = @"CRTwitterSelectNewTabsAndWindows";

NSString *CRTwitterSelectedUsernameDidChangeNotification = @"CRTwitterSelectedUsernameDidChangeNotification";
NSString *CRTwitterDisplayUsernamesDidChangeNotification = @"CRTwitterDisplayUsernamesDidChangeNotification";

static CRTwitterPlugIn *instance = nil;

@implementation CRTwitterPlugIn

+ (void)load {
    if ([CRTwitterPlugIn class] == self) {

        NSDictionary *d = [NSDictionary dictionaryWithObjectsAndKeys:
                           [NSNumber numberWithBool:YES], kCRTwitterDisplayUsernamesKey,
                           [NSNumber numberWithBool:YES], kCRTwitterSelectNewTabsAndWindowsKey,
                           nil];
        [[NSUserDefaultsController sharedUserDefaultsController] setInitialValues:d];
        [[NSUserDefaults standardUserDefaults] registerDefaults:d];
        
    }
}


+ (CRTwitterPlugIn *)instance {
    return instance;
}


- (id)initWithPlugInAPI:(id <FUPlugInAPI>)api {
    if (self = [super initWithPlugInAPI:api]) {
        
        // set instance
        instance = self;

        self.plugInAPI = api;
        
        self.identifier = @"com.fluidapp.TwitterPlugIn";
        self.localizedTitle = @"Twitter";
        self.preferredMenuItemKeyEquivalent = @"t";
        self.preferredMenuItemKeyEquivalentModifierFlags = (NSControlKeyMask|NSAlternateKeyMask|NSCommandKeyMask);
        self.toolbarIconImageName = @"toolbar_button_twitter";
        self.preferencesIconImageName = @"toolbar_button_twitter";
        self.allowedViewPlacement = FUPlugInViewPlacementAny;
        
        self.preferredViewPlacement = FUPlugInViewPlacementSplitViewLeft;
        
        self.preferencesViewController = [[[CRTwitterPlugInPrefsViewController alloc] init] autorelease];
        
        NSBundle *bundle = [NSBundle bundleForClass:[self class]];
        NSString *path = [bundle pathForResource:@"CRTwitterDefaultValues" ofType:@"plist"];
        self.defaultsDictionary = [NSDictionary dictionaryWithContentsOfFile:path];
        self.preferredVerticalSplitPosition = 320;
        self.preferredHorizontalSplitPosition = 160;
        self.sortOrder = 300;
    }
    return self;
}


- (void)dealloc {
    self.plugInAPI = nil;    
    self.frontViewController = nil;
    self.selectedUsername = nil;
    [super dealloc];
}


- (void)setAboutInfoDictionary:(NSDictionary *)info {
    if (aboutInfoDictionary != info) {
        [aboutInfoDictionary autorelease];
        aboutInfoDictionary = [info retain];
    }
}


- (NSDictionary *)aboutInfoDictionary {
    if (!aboutInfoDictionary) {
        NSString *credits = [[[NSAttributedString alloc] initWithString:@"" attributes:nil] autorelease];
        NSString *applicationName = [NSString stringWithFormat:@"%@ Twitter Plug-in", [plugInAPI appName]];

        NSBundle *bundle = [NSBundle bundleForClass:[self class]];
        NSURL *URL = [NSURL fileURLWithPath:[bundle pathForImageResource:self.preferencesIconImageName]];
        NSImage  *applicationIcon = [[[NSImage alloc] initWithContentsOfURL:URL] autorelease];
        
        NSString *version = @"1.0";
        NSString *copyright = @"Todd Ditchendorf 2010";
        NSString *applicationVersion = @"1.0";
        
        self.aboutInfoDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
                                    credits, @"Credits",
                                    applicationName, @"ApplicationName",
                                    applicationIcon, @"ApplicationIcon",
                                    version, @"Version",
                                    copyright, @"Copyright",
                                    applicationVersion, @"ApplicationVersion",
                                    nil];
    }
    return aboutInfoDictionary;
}


- (void)showPrefs:(id)sender {
    [[self plugInAPI] showPreferencePaneForIdentifier:[self identifier]];
}


- (BOOL)tabbedBrowsingEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"FUTabbedBrowsingEnabled"];
}


- (BOOL)selectNewWindowsOrTabsAsCreated {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"FUSelectNewWindowsOrTabsAsCreated"];
}


- (void)openURLString:(NSString *)s {
    [self openURL:[NSURL URLWithString:s]];
}


- (void)openURL:(NSURL *)URL {
    NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:
                          URL, @"URL", [NSApp currentEvent], @"evt", nil];

    [self openURLWithArgs:args];
}


- (void)openURLWithArgs:(NSDictionary *)args {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread:@selector(openURLWithArgs:) withObject:args waitUntilDone:NO];
        return;
    }
    
    NSURL *URL = [args objectForKey:@"URL"];
    NSEvent *evt = [args objectForKey:@"evt"];
    
    // foreground or background?
    BOOL middleButtonClick = (2 == [evt buttonNumber]);
    BOOL commandKeyWasPressed = [self wasCommandKeyPressed:[evt modifierFlags]];
    BOOL shiftKeyWasPressed = [self wasShiftKeyPressed:[evt modifierFlags]];

    BOOL inForeground = YES; // tabs will be opened in the foregrand by default from this plugin

    BOOL commandClick = (commandKeyWasPressed | middleButtonClick); 
    if (commandClick) {
        inForeground = [self selectNewWindowsOrTabsAsCreated]; // we only check selectNewTabsOrWindows preference if commandClick was done
                                                               // why? cuz it just feels right
    }
    
    inForeground = (shiftKeyWasPressed) ? !inForeground : inForeground;
    
    // tab or window ?    
    BOOL tabbedBrowsingEnabled = [self tabbedBrowsingEnabled];
    BOOL optionKeyWasPressed = [self wasOptionKeyPressed:[evt modifierFlags]];
    tabbedBrowsingEnabled = (optionKeyWasPressed) ? !tabbedBrowsingEnabled : tabbedBrowsingEnabled;
    
    if (tabbedBrowsingEnabled) {
        [self openURL:URL inNewTabInForeground:inForeground];
    } else {
        [self openURL:URL inNewWindowInForeground:inForeground];
    }
}


- (BOOL)wasCommandKeyPressed:(NSInteger)modifierFlags {
    NSInteger commandKeyWasPressed = (NSCommandKeyMask & modifierFlags);
    return [[NSNumber numberWithInteger:commandKeyWasPressed] boolValue];
}


- (BOOL)wasShiftKeyPressed:(NSInteger)modifierFlags {
    NSInteger commandKeyWasPressed = (NSShiftKeyMask & modifierFlags);
    return [[NSNumber numberWithInteger:commandKeyWasPressed] boolValue];
}


- (BOOL)wasOptionKeyPressed:(NSInteger)modifierFlags {
    NSInteger commandKeyWasPressed = (NSAlternateKeyMask & modifierFlags);
    return [[NSNumber numberWithInteger:commandKeyWasPressed] boolValue];
}


- (void)openURL:(NSURL *)URL inNewTabInForeground:(BOOL)inForeground {
    [plugInAPI loadURL:[URL absoluteString] destinationType:FUPlugInDestinationTypeTab inForeground:inForeground];
}


- (void)openURL:(NSURL *)URL inNewWindowInForeground:(BOOL)inForeground {
    [plugInAPI loadURL:[URL absoluteString] destinationType:FUPlugInDestinationTypeWindow inForeground:inForeground];
}


- (void)showStatusText:(NSString *)s {
    [plugInAPI showStatusText:s];
}


#pragma mark -
#pragma mark FUPlugIn

- (NSViewController *)newPlugInViewController {
    CRTwitterPlugInViewController *vc = [[CRTwitterPlugInViewController alloc] init];
    vc.plugIn = self;
    self.frontViewController = vc;
    return vc;
}


#pragma mark -
#pragma mark FUPlugInNotifications

- (void)plugInViewControllerWillAppear:(NSNotification *)n {
    CRTwitterPlugInViewController *vc = (CRTwitterPlugInViewController *)[n object];
    [vc willAppear];
}


- (void)plugInViewControllerDidAppear:(NSNotification *)n {
    CRTwitterPlugInViewController *vc = (CRTwitterPlugInViewController *)[n object];
    [vc didAppear];
}


- (void)plugInViewControllerWillDisappear:(NSNotification *)n {
    CRTwitterPlugInViewController *vc = (CRTwitterPlugInViewController *)[n object];
    [vc willDisappear];
}


- (void)plugInViewControllerDidDisappear:(NSNotification *)n {
    CRTwitterPlugInViewController *vc = (CRTwitterPlugInViewController *)[n object];
    [vc didDisappear];
}


- (NSArray *)usernames {
    return [(CRTwitterPlugInPrefsViewController *)preferencesViewController usernames];
}


- (NSString *)passwordFor:(NSString *)username {
    return [(CRTwitterPlugInPrefsViewController *)preferencesViewController passwordFor:username];
}


- (NSString *)selectedUsername {
    if (selectedUsername) {
        return [[selectedUsername retain] autorelease];
    } else {
        NSArray *usernames = [self usernames];
        if ([usernames count]) {
            return [usernames objectAtIndex:0];
        } else {
            return nil;
         }
    }
}

@synthesize plugInAPI;
@synthesize frontViewController;
@synthesize selectedUsername;
@end
