#import <AppKit/AppKit.h>
#include "bridge.h"
#include <stdlib.h>
#include <string.h>
#include <atomic>
static std::atomic<NSInteger> lastChange;
static NSStatusItem *tray;
static NSMenuItem *connection;
static NSMutableArray<NSString*> *history;
@interface ClipboardApp : NSObject<NSApplicationDelegate>
@property NSTimer *timer;
@property BOOL showingLogin;
@end
@interface ClipboardApp (History)
-(void)presentHistory;
@end
@implementation ClipboardApp
-(void)applicationDidFinishLaunching:(NSNotification*)notice {
 [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
 tray=[[NSStatusBar systemStatusBar]statusItemWithLength:NSVariableStatusItemLength];tray.button.title=@"▣";tray.button.toolTip=@"共享剪贴板";
 NSMenu *menu=[NSMenu new];connection=[[NSMenuItem alloc]initWithTitle:@"正在启动" action:nil keyEquivalent:@""];[menu addItem:connection];
 for(NSArray *entry in @[@[@"登录 / 切换账号",NSStringFromSelector(@selector(login))],@[@"历史记录",NSStringFromSelector(@selector(showHistory))],@[@"解锁旧记录",NSStringFromSelector(@selector(unlock))],@[@"同步当前剪贴板",NSStringFromSelector(@selector(sync))],@[@"暂停 / 恢复",NSStringFromSelector(@selector(pause))],@[@"退出登录",NSStringFromSelector(@selector(logout))],@[@"退出",NSStringFromSelector(@selector(quit))]]){
  NSMenuItem *item=[[NSMenuItem alloc]initWithTitle:entry[0] action:NSSelectorFromString(entry[1]) keyEquivalent:@""];item.target=self;[menu addItem:item];
 }
 tray.menu=menu;lastChange=NSPasteboard.generalPasteboard.changeCount;
 self.timer=[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(tick) userInfo:nil repeats:YES];self.timer.tolerance=.25;
 [[[NSWorkspace sharedWorkspace]notificationCenter]addObserver:self selector:@selector(sleep:) name:NSWorkspaceWillSleepNotification object:nil];
 [[[NSWorkspace sharedWorkspace]notificationCenter]addObserver:self selector:@selector(wake:) name:NSWorkspaceDidWakeNotification object:nil];
 sc_start();
 if([NSProcessInfo.processInfo.arguments containsObject:@"--login"])[self login];
 if([NSProcessInfo.processInfo.arguments containsObject:@"--history"])sc_event(5,"");
}
-(void)tick {NSInteger revision=NSPasteboard.generalPasteboard.changeCount;if(revision!=lastChange){lastChange=revision;sc_event(2,"");}}
-(void)sleep:(NSNotification*)n {[self.timer invalidate];self.timer=nil;}
-(void)wake:(NSNotification*)n {lastChange=NSPasteboard.generalPasteboard.changeCount;self.timer=[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(tick) userInfo:nil repeats:YES];self.timer.tolerance=.25;}
-(BOOL)applicationShouldHandleReopen:(NSApplication*)app hasVisibleWindows:(BOOL)visible {if(!visible)[self login];return YES;}
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
-(void)showHistory{sc_event(5,"");}
-(void)sync{sc_event(2,"");}
-(void)pause{sc_event(7,"");}
-(void)logout{sc_event(8,"");}
-(void)quit{native_ws_close();[NSApp terminate:nil];}
@end
extern "C" int native_run(){@autoreleasepool{NSString *bundle=NSBundle.mainBundle.bundleIdentifier;if(bundle&&[NSRunningApplication runningApplicationsWithBundleIdentifier:bundle].count>1)return 0;NSApplication *app=[NSApplication sharedApplication];ClipboardApp *delegate=[ClipboardApp new];app.delegate=delegate;[app run];return 0;}}
extern "C" void native_status(const char *text){NSString *s=@(text);dispatch_async(dispatch_get_main_queue(),^{connection.title=s;tray.button.toolTip=[@"共享剪贴板 · " stringByAppendingString:s];if([s isEqualToString:@"请登录同一个账号"])[(ClipboardApp*)NSApp.delegate performSelectorOnMainThread:@selector(login) withObject:nil waitUntilDone:NO];});}
extern "C" void native_history_begin(){dispatch_async(dispatch_get_main_queue(),^{history=[NSMutableArray new];});}
extern "C" void native_history_item(const char*, const char *text){NSString *s=@(text);dispatch_async(dispatch_get_main_queue(),^{[history addObject:s];});}
extern "C" void native_history_end(){dispatch_async(dispatch_get_main_queue(),^{[(ClipboardApp*)NSApp.delegate performSelectorOnMainThread:@selector(presentHistory) withObject:nil waitUntilDone:NO];});}
@implementation ClipboardApp (History)
-(void)presentHistory {
 NSAlert *alert=[NSAlert new];alert.messageText=@"历史记录";alert.informativeText=@"选择一条复制；关闭后释放历史内容。";[alert addButtonWithTitle:@"复制"];[alert addButtonWithTitle:@"关闭"];
 NSPopUpButton *list=[[NSPopUpButton alloc]initWithFrame:NSMakeRect(0,0,500,30) pullsDown:NO];[list addItemsWithTitles:history.count?history:@[@"暂无记录"]];alert.accessoryView=list;
 [NSApp activateIgnoringOtherApps:YES];if([alert runModal]==NSAlertFirstButtonReturn&&history.count)sc_history_select((int)list.indexOfSelectedItem);
 sc_event(9,"");history=nil;
}
@end
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

extern "C" void native_detail(const char*,const char*,const unsigned char*,size_t,int){}
extern "C" void native_session(int){}
