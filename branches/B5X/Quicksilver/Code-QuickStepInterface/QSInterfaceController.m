#import "QSPreferenceKeys.h"
#import "QSInterfaceController.h"
#import "QSHistoryController.h"
#import <Carbon/Carbon.h>
#import "QSObject.h"

#import "QSActionProvider.h"

#import "QSTypes.h"
#import "QSTaskController.h"
#import "QSNotifications.h"

#import "QSObjectCell.h"
#import "QSCommand.h"
#import "QSInterfaceController.h"

#import "QSObject_FileHandling.h"

#import "QSTaskViewer.h"
#import "QSNullObject.h"
#import "QSTaskController.h"
#import "QSController.h"
#import "QSInterfaceController.h"

#import "QSAction.h"
#import "QSWindow.h"
#import "QSSearchObjectView.h"
#import "QSMnemonics.h"
#import "QSLibrarian.h"
#import <QSCore/QSExecutor.h>
#import <IOKit/IOCFBundle.h>
#import <ApplicationServices/ApplicationServices.h>

#import "QSTextProxy.h"
#import "QSMenuButton.h"

#define KeyShift	0x38
#define KeyControl	0x3b
#define KeyOption	0x3A
#define KeyCommand	0x37
#define KeyCapsLock	0x39
#define KeySpace	0x31
#define KeyTabs		0x30

#import "CGSPrivate.h"

typedef enum {
	CGSGlobalHotKeyEnable = 0,
	CGSGlobalHotKeyDisable = 1,
} CGSGlobalHotKeyOperatingMode;

extern CGSConnection _CGSDefaultConnection(void);
extern CGError CGSGetGlobalHotKeyOperatingMode(CGSConnection connection, CGSGlobalHotKeyOperatingMode *mode);
extern CGError CGSSetGlobalHotKeyOperatingMode(CGSConnection connection, CGSGlobalHotKeyOperatingMode mode);

@implementation QSInterfaceController

+ (void)initialize {
	static BOOL initialized = NO;
	if (initialized) return;
	initialized = YES;
	[NSApp registerServicesMenuSendTypes:[NSArray arrayWithObjects:NSStringPboardType, NSRTFPboardType, nil] returnTypes:[NSArray arrayWithObjects:NSStringPboardType, NSRTFPboardType, nil]];
}

+ (NSString *)name { return @"DefaultInterface"; }

- (id)initWithWindow:(NSWindow *)window {
	if (!(self = [super initWithWindow:window]) ) return nil;
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(windowDidBecomeKey:) name:NSWindowDidBecomeKeyNotification object:nil];
	[nc addObserver:self selector:@selector(windowDidResignKey:) name:NSWindowDidResignKeyNotification object:nil];
	[nc addObserver:self selector:@selector(objectModified:) name:@"ObjectModified" object:nil];
	[nc addObserver:self selector:@selector(searchObjectChanged:) name:@"SearchObjectChanged" object:nil];
	[nc addObserver:self selector:@selector(appChanged:) name:QSActiveApplicationChanged object:nil];
  if (fALPHA)
	  [QSHistoryController sharedInstance];
	return self;
}

- (void)dealloc {
	if([actionsUpdateTimer isValid])
		[actionsUpdateTimer invalidate];
	if([hideTimer isValid])
		[hideTimer invalidate];
	if([clearTimer isValid])
		[clearTimer invalidate];
	[actionsUpdateTimer release];
	[hideTimer release];
	[clearTimer release];
	[progressIndicator release];
	[iSelector release];
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc removeObserver:progressIndicator];
	[nc removeObserver:self];
	[[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

- (NSSize) maxIconSize {
	return NSMakeSize(128, 128);
}
- (void)windowDidLoad {
	//if (![[self window] setFrameUsingName:[self window] Key]) [[self window] center];
	[progressIndicator stopAnimation:self];
	[progressIndicator setDisplayedWhenStopped:NO];
	[aSelector setEnabled:NO];
	[aSelector setAllowText:NO];
	// [aSelector setInitiatesDrags:NO];
	[aSelector setDropMode:QSRejectDropMode];

	[aSelector setSearchMode:SearchFilter];
	[aSelector setAllowNonActions:NO];

	[iSelector retain];
	[self hideIndirectSelector:nil];

	[[self window] setHidesOnDeactivate:NO];
	[[self menuButton] setMenu:[(QSController *)[NSApp delegate] statusMenuWithQuit]];

#if 0
	QSObjectCell *attachmentCell = [[QSObjectCell alloc] initTextCell:@""];
	[attachmentCell setRepresentedObject:[QSObject fileObjectWithPath:@"/Volumes/Lore/"]];
	[[attachmentCell representedObject] loadIcon];

	NSTextAttachment *attachment = [[[NSTextAttachment alloc] init] autorelease];
	[attachment setAttachmentCell: attachmentCell];
#endif

	// NSAttributedString *attributedString = [NSAttributedString attributedStringWithAttachment: attachment];
	//[[commandView textStorage] appendAttributedString:attributedString];
	[self searchObjectChanged:nil];

	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:progressIndicator selector:@selector(startAnimation:) name:QSTasksStartedNotification object:nil];
	[nc addObserver:progressIndicator selector:@selector(stopAnimation:) name:QSTasksEndedNotification object:nil];
}

- (IBAction)hideWindows:(id)sender {
	[self hideMainWindow:self];
	[[NSNotificationCenter defaultCenter] postNotificationName:QSReleaseOldCachesNotification object:self];
	[self setClearTimer];
}

// Menu Actions

- (void)selectObject:(QSBasicObject *)object {
	[dSelector setObjectValue:object];
}

- (QSBasicObject *)selection {
	return [dSelector objectValue];
}

- (void)shortCircuit:(id)sender {
	//NSLog(@"scirr");
	[self fireActionUpdateTimer];
	NSArray *array = [aSelector resultArray];

	int argumentCount = [(QSAction *)[aSelector objectValue] argumentCount];

	if (sender == iSelector) {
		int index = [array indexOfObject:[aSelector objectValue]];
		int count = [array count];
		if (index != count-1)
			array = [[array subarrayWithRange:NSMakeRange(index+1, count-index-1)] arrayByAddingObjectsFromArray:
				[array subarrayWithRange:NSMakeRange(0, index+1)]];
		argumentCount = 0;
		[[self window] makeFirstResponder:nil];
	}

	if (argumentCount != 2) {
		NSEnumerator *enumer = [array objectEnumerator];
		QSAction *action = nil;
		QSAction *bestAction = nil;
		while(action = [enumer nextObject]) {
			if ([action argumentCount] == 2) {
				bestAction = action;
				[aSelector selectObject:action];
				[self updateIndirectObjects];
				break;
			}
		}
		if (!bestAction) {
			NSBeep();
			return;
		}
	}
	[[self window] makeFirstResponder:iSelector];
}

- (void)updateActions {
	[aSelector setResultArray:nil];
	[aSelector clearObjectValue];
	[self performSelectorOnMainThread:@selector(setActionUpdateTimer) withObject:nil waitUntilDone:YES];
}

- (void)setActionUpdateTimer {
	if ([actionsUpdateTimer isValid]) {
		// *** this was causing actions not to update for the search contents action
		[actionsUpdateTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:0.30]];
		//[actionsUpdateTimer fire];
		//	NSLog(@"action %@", [actionsUpdateTimer fireDate]);
	} else {
		[actionsUpdateTimer invalidate];
		[actionsUpdateTimer release];
		actionsUpdateTimer = [[NSTimer scheduledTimerWithTimeInterval:0.30 target:self selector:@selector(updateActionsNow) userInfo:nil repeats:NO] retain];
	}
}

- (void)fireActionUpdateTimer {
	[actionsUpdateTimer fire];
}

- (void)updateControl:(QSSearchObjectView *)control withArray:(NSArray *)array {
	id defaultSelection = nil;
	if ([array count]) {
		if ([[array lastObject] isKindOfClass:[NSArray class]]) {
			defaultSelection = [array objectAtIndex:0];
			if ([defaultSelection isKindOfClass:[NSNull class]])
				defaultSelection = nil;
			array = [array lastObject];

		} else {
			defaultSelection = [array objectAtIndex:0];
		}
	} else {
		[control clearObjectValue];
	}
	[control clearSearch];
	[control setSourceArray:(NSMutableArray *)array];
	[control setResultArray:(NSMutableArray *)array];

	[control selectObject:defaultSelection];
}

- (NSArray *)rankedActions {
	return [QSExec rankedActionsForDirectObject:[dSelector objectValue] indirectObject:[iSelector objectValue]];
}
- (void)updateActionsNow {
	[actionsUpdateTimer invalidate];

	[aSelector setEnabled:YES];
	NSString *type = [NSString stringWithFormat:@"QSActionMnemonic:%@", [[dSelector objectValue] primaryType]];
	NSArray *actions = [self rankedActions];

	[self updateControl:aSelector withArray:actions];

	[aSelector setMatchedString:type];
	[aSelector setSearchString:nil];
}

- (void)updateIndirectObjects {
	NSArray *indirects = [[[aSelector objectValue] provider] validIndirectObjectsForAction:[[aSelector objectValue] identifier] directObject:[dSelector objectValue]];
	[self updateControl:iSelector withArray:indirects];
	[iSelector setSearchMode:(indirects?SearchFilter:SearchFilterAll)];
}

- (void)clearObjectView:(QSSearchObjectView *)view {
	[view setResultArray:nil];
	[view setSourceArray:nil];
	[view setMatchedString:nil];
	[view setSearchString:nil];
	[view clearObjectValue];
}

- (void)searchArray:(NSMutableArray *)array {
	[actionsUpdateTimer invalidate];
	[self clearObjectView:dSelector];
	//[self clearObjectView:aSelector];
	[dSelector setSourceArray:array]; // !!!:nicholas:20040319
	[dSelector setResultArray:array]; // !!!:nicholas:20040319
	[self updateViewLocations];
	[self updateActionsNow];
	[self showMainWindow:self];
	[[self window] makeFirstResponder:dSelector];
	[dSelector setSearchMode:SearchFilter];
}

- (void)showArray:(NSArray *)array {
	[actionsUpdateTimer invalidate];
    NSMutableArray *mutArray = [[array mutableCopy] autorelease];
	[self clearObjectView:dSelector];
	//[self clearObjectView:aSelector];
	[dSelector setSourceArray:mutArray]; // !!!:nicholas:20040319
	[dSelector setResultArray:mutArray]; // !!!:nicholas:20040319
	[dSelector setSearchMode:SearchFilter];
	if ([mutArray count])
		[dSelector selectObject:[mutArray objectAtIndex:0]];
	[self updateViewLocations];
	[self updateActionsNow];
	[self showMainWindow:self];
	[[self window] makeFirstResponder:dSelector];
	[dSelector showResultView:self];
}

- (void)showInterface:(id)sender {
	[[NSNotificationCenter defaultCenter] postNotificationName:@"InterfaceActivated" object:self];
	[self showMainWindow:self];
}

- (id)init {
	if (self = [super init]) {
		[self loadWindow];
	}
	return self;
}

- (void)activate:(id)sender {
	if ([[self window] isVisible] && [[NSUserDefaults standardUserDefaults] boolForKey:@"QSInterfaceReactivationDeactivates"]) {
		[self hideMainWindowFromCancel:sender];
		return;
	}

	[[NSNotificationCenter defaultCenter] postNotificationName:@"InterfaceActivated" object:self];

	[hideTimer invalidate];
	[dSelector reset:self];
	[self updateActions];
	[iSelector reset:self];
	[[dSelector objectValue] loadIcon];
	[self setPreview:NO];
	[self showInterface:self];

	[[self window] makeFirstResponder:dSelector];

	[dSelector setSearchMode:SearchFilterAll];

	NSEvent *theEvent = [NSApp nextEventMatchingMask:NSKeyDownMask untilDate:[NSDate dateWithTimeIntervalSinceNow:0.075] inMode:NSDefaultRunLoopMode dequeue:YES];
#warning dont do this unless the character is alphabetic
	if (theEvent) {
		theEvent = [NSEvent keyEventWithType:[theEvent type] location:[theEvent locationInWindow] modifierFlags:0 timestamp:[theEvent timestamp] windowNumber:[theEvent windowNumber] context:[theEvent context] characters:[theEvent charactersIgnoringModifiers] charactersIgnoringModifiers:[theEvent charactersIgnoringModifiers] isARepeat:[theEvent isARepeat] keyCode:[theEvent keyCode]];
		if (VERBOSE) NSLog(@"Ignoring Modifiers for characters: %@", [theEvent characters]);
		[NSApp postEvent:theEvent atStart:YES];
		//NSLog(@"time2 %f", [theEvent timestamp]);
	}
}

- (void)actionActivate:(id)sender {
	[self updateActionsNow];
	[iSelector reset:self];
	[[dSelector objectValue] loadIcon];
	[[self window] makeFirstResponder:aSelector];
	[self showInterface:self];
}

- (void)activateInTextMode:(id)sender {
	[dSelector transmogrify:sender];
	[iSelector reset:self];
	[self showInterface:self];
}

- (void)willHideMainWindow:(id)sender {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:kSuppressHotKeysInCommand]) {
		CGSConnection conn = _CGSDefaultConnection();
		CGSSetGlobalHotKeyOperatingMode(conn, CGSGlobalHotKeyEnable);
	}
	if ([[self window] isVisible] && ![[self window] attachedSheet]) {
		[[NSNotificationCenter defaultCenter] postNotificationName:@"InterfaceDeactivated" object:self];
		[[self window] makeFirstResponder:nil];
	}
}

- (void)hideMainWindowWithEffect:(id)effect {
	[self willHideMainWindow:nil];
	hidingWindow = YES;
	if (effect && [[NSUserDefaults standardUserDefaults] boolForKey:kUseEffects])
		[(QSWindow *)[self window] hideWithEffect:effect];
	else
		[(QSWindow *)[self window] orderOut:nil];
	hidingWindow = NO;
	[[NSNotificationCenter defaultCenter] postNotificationName:QSReleaseOldCachesNotification object:self];

}
- (void)hideMainWindow:(id)sender {
	[self hideMainWindowWithEffect:nil];
}
- (void)hideMainWindowFromExecution:(id)sender {
	[self hideMainWindowWithEffect:
		[[self window] windowPropertyForKey:kQSWindowExecEffect]];
}
- (void)hideMainWindowFromCancel:(id)sender {
	[self hideMainWindowWithEffect:
		[[self window] windowPropertyForKey:kQSWindowCancelEffect]];
}
- (void)hideMainWindowFromFade:(id)sender {
	if ([[self window] respondsToSelector:@selector(windowPropertyForKey:)])
		[self hideMainWindowWithEffect:
			[[self window] windowPropertyForKey:kQSWindowFadeEffect]];
}

- (void)showMainWindow:(id)sender {
	[(QSWindow *)[self window] makeKeyAndOrderFront:sender];
	if ([[NSUserDefaults standardUserDefaults] boolForKey:kSuppressHotKeysInCommand]) {
		CGSConnection conn = _CGSDefaultConnection();
		CGSSetGlobalHotKeyOperatingMode(conn, CGSGlobalHotKeyDisable);
	}
}

- (void)performService:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error {
	QSObject *entry;
	entry = [[QSObject alloc] initWithPasteboard:pboard];
	[dSelector setObjectValue:entry];
	[entry release];
	[self activate:self];
}

- (void)objectModified:(NSNotification*)notif {
	if ([[dSelector objectValue] isEqual:[notif object]]) {
		if (VERBOSE) NSLog(@"Reloading actions for: %@", [notif object]);
		[self updateActions];
	}
}

- (void)searchObjectChanged:(NSNotification*)notif {
	[[self window] disableFlushWindow];
	if ([notif object] == dSelector) {
		[iSelector setObjectValue:nil];
		[self updateActions];
		[self updateViewLocations];
	} else if ([notif object] == aSelector) {
		int argumentCount = [(QSAction *)[aSelector objectValue] argumentCount];
		if (argumentCount == 2)
			[self updateIndirectObjects];
		[self updateViewLocations];
	} else if ([notif object] == iSelector) {
		[self updateViewLocations];
	}
	[[self window] enableFlushWindow];
}

- (void)updateViewLocations {
	if ([(QSAction *)[aSelector objectValue] argumentCount] == 2)
		[self showIndirectSelector:nil];
	else
		[self hideIndirectSelector:nil];
}

- (void)showIndirectSelector:(id)sender {
	[[[self window] contentView] addSubview:iSelector];
	[aSelector setNextKeyView:iSelector];
}

- (void)hideIndirectSelector:(id)sender {
	[iSelector removeFromSuperview];
}

//Notifications
#pragma mark Notifications


- (void)appChanged:(NSNotification *)aNotification {
	NSString *currentApp = [[[NSWorkspace sharedWorkspace] activeApplication] objectForKey:@"NSApplicationBundleIdentifier"];
	if (![currentApp isEqualToString:@"com.blacktree.Quicksilver"])
		[self hideWindows:self];
}

- (IBAction)showAbout:(id)sender {
	[[NSApp delegate] showAbout:sender];
}

- (void)invalidateHide {
	[hideTimer invalidate];
}

- (void)timerHide:(NSTimer *)timer {
	if (preview) return;
	bool stayOpen = StillDown();
	if (!stayOpen) {
		 // NSLog(@"Window Closing");
		if ([[NSApp keyWindow] level] <= [[self window] level])
			// ***warning  * this needs to be better
			[self hideMainWindowFromFade:self];
		[hideTimer invalidate];
	} else {
		//	NSLog(@"Window Staying Open");
	}
}
- (void)dragPerformed {
	// NSLog(@"perform"); [hideTimer invalidate];
}

- (void)windowDidResignMain:(NSNotification *)aNotification {
	// if (VERBOSE)  NSLog(@"ResignMain");
}

- (BOOL)windowShouldClose:(id)sender {
	[self hideMainWindowFromCancel:self];
	return NO;
}

- (void)windowDidResignKey:(NSNotification *)aNotification {
	if ([aNotification object] == [self window]) {
		if (hidingWindow) return;
		if ([hideTimer isValid]) {
			[hideTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
		} else {
			[hideTimer release];
			hideTimer = [[NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(timerHide:) userInfo:nil repeats:YES] retain];
			[hideTimer fire];
		}
	} else if (![NSApp keyWindow]) {
		[self hideMainWindowFromFade:self];
	}
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
	NSWindow *window = [notification object];
	if ([[self window] attachedSheet] == window)
		return;
	if (window == [self window]) {
	 	[clearTimer invalidate];
		[hideTimer invalidate];
	} else if ([[notification object] level] <= [[self window] level]) {
		//NSLog(@"hide! %@", window);
		// ***warning  * this needs to be better
		[self hideWindows:self];
	}
}

- (void)setClearTimer {
	if ([clearTimer isValid]) {
		[clearTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:10*MINUTES]];
	} else {
		[clearTimer release];
		clearTimer = [[NSTimer scheduledTimerWithTimeInterval:10*MINUTES target:self selector:@selector(clear:) userInfo:nil repeats:NO] retain];
	}
}

- (void)clear:(NSTimer *)timer {
	[dSelector clearObjectValue];
	[self updateActionsNow];
}

- (IBAction)showTasks:(id)sender {
	[[NSClassFromString(@"QSTaskViewer") sharedInstance] showWindow:self];
}

- (NSProgressIndicator *)progressIndicator { return progressIndicator;  }

- (void)setCommandWithArray:(NSArray *)array {
	[dSelector setObjectValue:[array objectAtIndex:0]];
	[actionsUpdateTimer invalidate];
	[aSelector setObjectValue:[array objectAtIndex:1]];
	if ([array count] >2)
		[iSelector setObjectValue:[array objectAtIndex:2]];
	else
		[iSelector setObjectValue:nil];
}

- (void)executePartialCommand:(NSArray *)array {
	[dSelector setObjectValue:[array objectAtIndex:0]];
	if ([array count] == 1) {
		[self updateActionsNow];
		[[self window] makeFirstResponder:aSelector];
	} else {
		[actionsUpdateTimer invalidate];
		[aSelector setObjectValue:[array objectAtIndex:1]];
		if ([array count] > 2) {
			[iSelector setObjectValue:[array objectAtIndex:2]];
		}
		[[self window] makeFirstResponder:iSelector];
	}
	[self updateViewLocations];
	[self showInterface:self];
}

- (IBAction)executeCommand:(id)sender cont:(BOOL)cont encapsulate:(BOOL)encapsulate {
	if ([actionsUpdateTimer isValid]) {
		[actionsUpdateTimer fire];
	}
	if (![aSelector objectValue]) {
		NSBeep();
		return;
	}
	int argumentCount = [(QSAction *)[aSelector objectValue] argumentCount];
	if (argumentCount == 2) {
		BOOL indirectIsRequired = ![[[[aSelector objectValue] actionDict] objectForKey:kActionIndirectOptional] boolValue];
		BOOL indirectIsInvalid = ![iSelector objectValue];
		BOOL indirectIsTextProxy = [[[iSelector objectValue] primaryType] isEqual:QSTextProxyType];
		if (indirectIsRequired && (indirectIsInvalid || indirectIsTextProxy) ) {
			if (![iSelector objectValue]) NSBeep();
			[[self window] makeFirstResponder:iSelector];
			return;
		}
		[QSExec noteIndirect:[iSelector objectValue] forAction:[aSelector objectValue]];
	}
	if (encapsulate) {
		[self encapsulateCommand];
		return;
	}
	if (!cont) [self hideMainWindowFromExecution:self]; // *** this should only hide if no result comes in like 2 seconds
	if ([[NSUserDefaults standardUserDefaults] boolForKey:kExecuteInThread] && [[aSelector objectValue] canThread])
		[NSThread detachNewThreadSelector:@selector(executeCommandThreaded) toTarget:self withObject:nil];
	else
		[self executeCommandThreaded];
	if (fALPHA)
		[QSHist addCommand:[self currentCommand]];
	[dSelector saveMnemonic];
 	[aSelector saveMnemonic];
	if (argumentCount == 2) [iSelector saveMnemonic];
	if (cont) [[self window] makeFirstResponder:aSelector];
}

- (void)encapsulateCommand:(id)sender {
	[self executeCommand:(id)sender cont:NO encapsulate:YES];
}

- (void)executeCommandAndContinue:(id)sender {
	[self executeCommand:(id)sender cont:YES encapsulate:NO];
}

- (IBAction)executeCommand:(id)sender {
	[self executeCommand:(id)sender cont:NO encapsulate:NO];
}

- (QSCommand *)currentCommand {
	return [QSCommand commandWithDirectObject:[dSelector objectValue] actionObject:[aSelector objectValue] indirectObject:[iSelector objectValue]];
}

- (void)setCommand:(QSCommand *)command {
	[self window];
	  [dSelector setObjectValue:[command dObject]];
	  [aSelector setObjectValue:[command aObject]];
	  [iSelector setObjectValue:[command iObject]];
}

- (void)encapsulateCommand {
	if (VERBOSE) NSLog(@"Encapsulating Command");
	QSCommand *command = [self currentCommand];
	QSObject *commandObject = [QSObject objectWithName:[command description]];
	[commandObject setObject:command forType:QSCommandType];

	[commandObject setPrimaryType:QSCommandType];
	[self selectObject:commandObject];
	[self actionActivate:commandObject];
}

- (void)executeCommandThreaded {
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	NSDate *startDate = [NSDate date];
	QSAction *action = [aSelector objectValue];
	if ([[NSApp currentEvent] modifierFlags] & NSCommandKeyMask && !([[NSApp currentEvent] modifierFlags] & NSShiftKeyMask) ) {
		action = [action alternate];
		if (VERBOSE) NSLog(@"Using Alternate: %@", action);
	}
	QSObject *returnValue = [action performOnDirectObject:[dSelector objectValue] indirectObject:[iSelector objectValue]];
	if (returnValue) {
		if ([returnValue isKindOfClass:[QSNullObject class]]) {
			[self clearObjectView:dSelector];
		} else {
			BOOL display = [[[action actionDict] objectForKey:kActionDisplaysResult] boolValue];
			[dSelector performSelectorOnMainThread:@selector(selectObjectValue:) withObject:returnValue waitUntilDone:YES];
			if (display) [self showMainWindow:self];
		}
	}
	if (VERBOSE) NSLog(@"Command executed (%dms) ", (int)(-[startDate timeIntervalSinceNow] *1000));
	[pool release];
}

- (BOOL)performKeyEquivalent:(NSEvent *)theEvent {
	if ([theEvent modifierFlags] & NSCommandKeyMask && [theEvent modifierFlags] & NSShiftKeyMask && [[theEvent characters] length] && [[NSCharacterSet letterCharacterSet] characterIsMember:[[theEvent characters] characterAtIndex:0]]) {
		return [[self aSelector] executeText:(NSEvent *)theEvent];
	}
	return NO;
}

- (QSSearchObjectView *)dSelector { return dSelector;  }

- (QSSearchObjectView *)aSelector { return aSelector;  }

- (QSSearchObjectView *)iSelector { return iSelector;  }

- (QSMenuButton *)menuButton { return menuButton;  }

- (BOOL)preview { return preview;  }
- (void)setPreview: (BOOL)flag {
	preview = flag;
}

-(void)setHiding:(BOOL)fl { hidingWindow = fl; }

@end