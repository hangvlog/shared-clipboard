#import <AppKit/AppKit.h>
@interface ClipboardWindow : NSWindowController<NSWindowDelegate,NSTableViewDataSource,NSTableViewDelegate>
@property BOOL loggedIn;
-(void)open;
/// Close the window and keep running in the menu bar only (no Dock icon).
-(void)hide;
-(void)clear;
-(void)status:(NSString*)text;
-(void)beginHistory;
-(void)addId:(NSString*)identifier label:(NSString*)label;
-(void)endHistory;
-(void)detailId:(NSString*)identifier text:(NSString*)text image:(NSData*)image success:(BOOL)success;
@end
