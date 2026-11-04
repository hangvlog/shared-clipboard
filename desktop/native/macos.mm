#import <AppKit/AppKit.h>
#import <ServiceManagement/ServiceManagement.h>
#include "bridge.h"
#import "macos_ui.h"
#include <stdlib.h>
#include <string.h>
#include <atomic>
static std::atomic<NSInteger> lastChange;
static NSStatusItem *tray;
static NSMenuItem *connection;
static ClipboardWindow *mainWindow;
@interface ClipboardApp : NSObject<NSApplicationDelegate>
@property NSTimer *timer;
@property BOOL showingLogin;
@property BOOL launchedAtLogin;
@property BOOL allowQuit;
@end
// Offer start-at-login once from /Applications; afterwards the user's choice in System Settings wins.
static void offerLoginItem(){
 NSUserDefaults *defaults=NSUserDefaults.standardUserDefaults;NSString *bundle=NSBundle.mainBundle.bundlePath;
 if([defaults boolForKey:@"loginItemOffered"]||!([bundle hasPrefix:@"/Applications/"]||[bundle hasPrefix:[NSHomeDirectory() stringByAppendingPathComponent:@"Applications/"]]))return;
 BOOL done=NO;
 // Runtime lookup instead of @available: the Rust link step does not pull in clang's version-check helper.
 Class serviceClass=NSClassFromString(@"SMAppService");
 if(serviceClass){
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
  SMAppService *service=[serviceClass mainAppService];done=service.status==SMAppServiceStatusEnabled||[service registerAndReturnError:nil];
#pragma clang diagnostic pop
 }
 else{
  NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/LaunchAgents"];[NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
  NSDictionary *agent=@{@"Label":@"chat.clawkit.shared-clipboard",@"ProgramArguments":@[NSBundle.mainBundle.executablePath,@"--background"],@"RunAtLoad":@YES};
  done=[agent writeToFile:[dir stringByAppendingPathComponent:@"chat.clawkit.shared-clipboard.plist"] atomically:YES];
 }
 if(done)[defaults setBool:YES forKey:@"loginItemOffered"];
}
// Log out, restart and shut down must never be blocked.
static BOOL systemQuit(){
 OSType why=[NSAppleEventManager.sharedAppleEventManager.currentAppleEvent attributeDescriptorForKeyword:kAEQuitReason].typeCodeValue;
 return why==kAELogOut||why==kAEReallyLogOut||why==kAEShowRestartDialog||why==kAERestart||why==kAEShowShutdownDialog||why==kAEShutDown;
}
@implementation ClipboardApp
-(void)applicationWillFinishLaunching:(NSNotification*)notice {
 NSAppleEventDescriptor *event=NSAppleEventManager.sharedAppleEventManager.currentAppleEvent;
 self.launchedAtLogin=[NSProcessInfo.processInfo.arguments containsObject:@"--background"]||(event.eventID==kAEOpenApplication&&[event paramDescriptorForKeyword:keyAEPropData].enumCodeValue==keyAELaunchedAsLogInItem);
}
-(void)applicationDidFinishLaunching:(NSNotification*)notice {
 [NSApp setActivationPolicy:self.launchedAtLogin?NSApplicationActivationPolicyAccessory:NSApplicationActivationPolicyRegular];
 tray=[[NSStatusBar systemStatusBar]statusItemWithLength:NSVariableStatusItemLength];
 NSImage *statusIcon=[[NSImage alloc]initWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"StatusIcon" ofType:@"png"]];
 if(statusIcon){statusIcon.size=NSMakeSize(18,18);[statusIcon setTemplate:YES];tray.button.image=statusIcon;}else{tray.button.title=@"▣";}
 tray.button.toolTip=@"共享剪贴板";
 NSMenu *menu=[NSMenu new];connection=[[NSMenuItem alloc]initWithTitle:@"正在启动" action:nil keyEquivalent:@""];[menu addItem:connection];
 for(NSArray *entry in @[@[@"登录 / 切换账号",NSStringFromSelector(@selector(login))],@[@"历史记录",NSStringFromSelector(@selector(showHistory))],@[@"解锁旧记录",NSStringFromSelector(@selector(unlock))],@[@"同步当前剪贴板",NSStringFromSelector(@selector(sync))],@[@"暂停 / 恢复",NSStringFromSelector(@selector(pause))],@[@"退出登录",NSStringFromSelector(@selector(logout))],@[@"退出",NSStringFromSelector(@selector(quit))]]){
  NSMenuItem *item=[[NSMenuItem alloc]initWithTitle:entry[0] action:NSSelectorFromString(entry[1]) keyEquivalent:@""];item.target=self;[menu addItem:item];
 }
 NSMenu *bar=[NSMenu new];NSMenuItem *appMenu=[NSMenuItem new];[bar addItem:appMenu];NSMenu *commands=[NSMenu new];NSMenuItem *open=[[NSMenuItem alloc]initWithTitle:@"打开共享剪贴板" action:@selector(showHistory) keyEquivalent:@"0"];open.target=self;[commands addItem:open];[commands addItem:NSMenuItem.separatorItem];NSMenuItem *exit=[[NSMenuItem alloc]initWithTitle:@"关闭窗口（菜单栏继续同步）" action:@selector(hideToMenuBar) keyEquivalent:@"q"];exit.target=self;[commands addItem:exit];appMenu.submenu=commands;NSApp.mainMenu=bar;
 tray.menu=menu;lastChange=NSPasteboard.generalPasteboard.changeCount;
 self.timer=[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(tick) userInfo:nil repeats:YES];self.timer.tolerance=.25;
 [[[NSWorkspace sharedWorkspace]notificationCenter]addObserver:self selector:@selector(sleep:) name:NSWorkspaceWillSleepNotification object:nil];
 [[[NSWorkspace sharedWorkspace]notificationCenter]addObserver:self selector:@selector(wake:) name:NSWorkspaceDidWakeNotification object:nil];
 [[[NSWorkspace sharedWorkspace]notificationCenter]addObserver:self selector:@selector(powerOff:) name:NSWorkspaceWillPowerOffNotification object:nil];
 [[NSDistributedNotificationCenter defaultCenter]addObserver:self selector:@selector(sessionChanged:) name:@"chat.clawkit.shared-clipboard.session" object:nil suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
 mainWindow=[ClipboardWindow new];sc_start();if(!self.launchedAtLogin)[mainWindow open];
 offerLoginItem();
 if([NSProcessInfo.processInfo.arguments containsObject:@"--login"])[self login];
 if([NSProcessInfo.processInfo.arguments containsObject:@"--history"])sc_event(5,"");
}
-(void)tick {NSInteger revision=NSPasteboard.generalPasteboard.changeCount;if(revision!=lastChange){lastChange=revision;sc_event(2,"");}}
-(void)sleep:(NSNotification*)n {[self.timer invalidate];self.timer=nil;}
-(void)wake:(NSNotification*)n {lastChange=NSPasteboard.generalPasteboard.changeCount;self.timer=[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(tick) userInfo:nil repeats:YES];self.timer.tolerance=.25;sc_event(14,"wake");}
-(void)applicationDidBecomeActive:(NSNotification*)n {sc_event(14,"active");}
-(void)sessionChanged:(NSNotification*)n {sc_event(15,"");}
-(BOOL)applicationShouldHandleReopen:(NSApplication*)app hasVisibleWindows:(BOOL)visible {[mainWindow open];return YES;}
-(void)login {
 if(self.showingLogin)return;self.showingLogin=YES;
 NSAlert *alert=[NSAlert new];alert.messageText=@"登录共享剪贴板";alert.informativeText=@"各设备使用同一账号即可同步；新内容无需设置加密密码。";
 [alert addButtonWithTitle:@"登录"];[alert addButtonWithTitle:@"取消"];
 NSView *form=[[NSView alloc]initWithFrame:NSMakeRect(0,0,340,72)];
 NSTextField *user=[[NSTextField alloc]initWithFrame:NSMakeRect(0,40,340,24)];user.placeholderString=@"账号";
 NSSecureTextField *password=[[NSSecureTextField alloc]initWithFrame:NSMakeRect(0,4,340,24)];password.placeholderString=@"登录密码";
 [form addSubview:user];[form addSubview:password];alert.accessoryView=form;
 [NSApp activateIgnoringOtherApps:YES];if([alert runModal]==NSAlertFirstButtonReturn)sc_login(user.stringValue.UTF8String,password.stringValue.UTF8String,"");
 self.showingLogin=NO;
}
-(void)unlock {
 NSAlert *alert=[NSAlert new];alert.messageText=@"解锁旧记录";alert.informativeText=@"仅用于读取旧内容，不影响新内容同步。";
 [alert addButtonWithTitle:@"解锁"];[alert addButtonWithTitle:@"取消"];
 NSSecureTextField *field=[[NSSecureTextField alloc]initWithFrame:NSMakeRect(0,0,340,24)];field.placeholderString=@"旧记录原来使用的密码";alert.accessoryView=field;
 [NSApp activateIgnoringOtherApps:YES];if([alert runModal]==NSAlertFirstButtonReturn)sc_event(11,field.stringValue.UTF8String);
}
-(void)showHistory{[mainWindow open];}
-(void)sync{sc_event(2,"");}
-(void)pause{sc_event(7,"");}
-(void)logout{sc_event(8,"");mainWindow.loggedIn=NO;[mainWindow clear];}
// Only the menu-bar "退出" ends the app; Dock Quit and ⌘Q keep it syncing in the menu bar.
-(void)quit{self.allowQuit=YES;native_ws_close();[NSApp terminate:nil];}
-(void)hideToMenuBar{[mainWindow hide];}
-(void)powerOff:(NSNotification*)n{self.allowQuit=YES;}
-(NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender{
 if(self.allowQuit||systemQuit())return NSTerminateNow;
 [mainWindow hide];return NSTerminateCancel;
}
@end
static BOOL reopenExistingApplication(){
 NSString *bundle=NSBundle.mainBundle.bundleIdentifier;if(!bundle)return NO;
 for(NSRunningApplication *running in [NSRunningApplication runningApplicationsWithBundleIdentifier:bundle]){
  if(running.processIdentifier==NSProcessInfo.processInfo.processIdentifier||running.terminated||!running.bundleURL)continue;
  // Opening the running bundle sends a reopen event, including when its window
  // was closed. Merely activating its process cannot reveal an ordered-out window.
  NSError *error=nil;
  NSRunningApplication *opened=[NSWorkspace.sharedWorkspace launchApplicationAtURL:running.bundleURL options:NSWorkspaceLaunchDefault configuration:@{} error:&error];
  if(opened){[opened activateWithOptions:NSApplicationActivateAllWindows|NSApplicationActivateIgnoringOtherApps];return YES;}
 }
 return NO;
}
extern "C" int native_run(){@autoreleasepool{if(reopenExistingApplication())return 0;NSApplication *app=[NSApplication sharedApplication];ClipboardApp *delegate=[ClipboardApp new];app.delegate=delegate;[app run];return 0;}}
extern "C" void native_status(const char *text){NSString *s=@(text);dispatch_async(dispatch_get_main_queue(),^{connection.title=s;tray.button.toolTip=[@"共享剪贴板 · " stringByAppendingString:s];[mainWindow status:s];});}
extern "C" void native_history_begin(){dispatch_async(dispatch_get_main_queue(),^{[mainWindow beginHistory];});}
extern "C" void native_history_item(const char *id,const char *text){NSString *identifier=@(id),*s=@(text);dispatch_async(dispatch_get_main_queue(),^{[mainWindow addId:identifier label:s];});}
extern "C" void native_history_end(){dispatch_async(dispatch_get_main_queue(),^{[mainWindow endHistory];});}
extern "C" char *native_clipboard_text(){@autoreleasepool{
 NSPasteboard *pb=NSPasteboard.generalPasteboard;
 if([pb.types containsObject:NSPasteboardTypeFileURL])return strdup("");
 return strdup(([pb stringForType:NSPasteboardTypeString]?:@"").UTF8String);
}}
extern "C" unsigned char *native_clipboard_png(size_t *length){@autoreleasepool{
 NSPasteboard *pb=NSPasteboard.generalPasteboard;*length=0;if([pb.types containsObject:NSPasteboardTypeFileURL])return nullptr;
 NSData *data=[pb dataForType:NSPasteboardTypePNG];
 if(!data){NSData *tiff=[pb dataForType:NSPasteboardTypeTIFF];if(tiff.length>32*1024*1024){*length=SIZE_MAX;return nullptr;}
  if(tiff){NSBitmapImageRep *image=[NSBitmapImageRep imageRepWithData:tiff];if(image.pixelsWide*image.pixelsHigh>16000000){*length=SIZE_MAX;return nullptr;}data=[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}];}}
 if(data.length>2*1024*1024){*length=SIZE_MAX;return nullptr;}if(!data)return nullptr;
 *length=data.length;auto *copy=(unsigned char*)malloc(*length);memcpy(copy,data.bytes,*length);return copy;
}}
@interface ClipboardWrite : NSObject
@property NSString *text;
@property NSData *image;
@property BOOL success;
-(void)apply;
@end
@implementation ClipboardWrite
-(void)apply {
 NSPasteboardItem *item=[NSPasteboardItem new];
 if(self.text.length)[item setString:self.text forType:NSPasteboardTypeString];
 if(self.image){const unsigned char *bytes=(const unsigned char*)self.image.bytes;NSString *type=(self.image.length>2&&bytes[0]==0xff&&bytes[1]==0xd8)?@"public.jpeg":NSPasteboardTypePNG;[item setData:self.image forType:type];}
 [NSPasteboard.generalPasteboard clearContents];self.success=[NSPasteboard.generalPasteboard writeObjects:@[item]];lastChange=NSPasteboard.generalPasteboard.changeCount;
}
@end
extern "C" int native_clipboard_write(const char *text,const unsigned char *image,size_t length){@autoreleasepool{
 ClipboardWrite *write=[ClipboardWrite new];write.text=@(text);write.image=length?[NSData dataWithBytes:image length:length]:nil;
 [write performSelectorOnMainThread:@selector(apply) withObject:nil waitUntilDone:YES modes:@[NSRunLoopCommonModes]];
 return write.success;
}}

extern "C" void native_clipboard_reset(){lastChange=NSPasteboard.generalPasteboard.changeCount;}

extern "C" void native_detail(const char *id,const char *text,const unsigned char *image,size_t length,int success){NSString *identifier=@(id),*value=@(text);NSData *bytes=length?[NSData dataWithBytes:image length:length]:nil;dispatch_async(dispatch_get_main_queue(),^{[mainWindow detailId:identifier text:value image:bytes success:success!=0];});}
extern "C" void native_session(int logged){dispatch_async(dispatch_get_main_queue(),^{mainWindow.loggedIn=logged!=0;[mainWindow clear];if(logged&&mainWindow.window.visible)sc_event(5,"");});}
