#import "macos_ui.h"
#import <QuartzCore/QuartzCore.h>
#include "bridge.h"
@interface ClipboardWindow ()
@property NSTableView *table;
@property NSTextView *text;
@property NSImageView *image;
@property NSTextField *statusLabel;
@property NSTextField *countLabel;
@property NSButton *duplicateButton;
@property NSMutableArray<NSString*> *ids;
@property NSMutableArray<NSString*> *labels;
@property NSString *selectedId;
@property BOOL loading;
@property NSString *connectionState;
@end
static NSTextField *label(NSString *value,CGFloat size,NSFontWeight weight){
 NSTextField *view=[NSTextField labelWithString:value];view.font=[NSFont systemFontOfSize:size weight:weight];view.lineBreakMode=NSLineBreakByTruncatingTail;return view;
}
static NSStackView *stack(NSArray<NSView*> *views,NSUserInterfaceLayoutOrientation orientation,CGFloat spacing){
 NSStackView *view=[NSStackView stackViewWithViews:views];view.orientation=orientation;view.spacing=spacing;view.alignment=orientation==NSUserInterfaceLayoutOrientationVertical?NSLayoutAttributeLeading:NSLayoutAttributeCenterY;view.translatesAutoresizingMaskIntoConstraints=NO;return view;
}
static NSView *card(NSView *child){
 NSVisualEffectView *view=[NSVisualEffectView new];view.material=NSVisualEffectMaterialContentBackground;view.blendingMode=NSVisualEffectBlendingModeWithinWindow;view.state=NSVisualEffectStateActive;view.wantsLayer=YES;view.layer.cornerRadius=18;view.layer.masksToBounds=YES;view.translatesAutoresizingMaskIntoConstraints=NO;child.translatesAutoresizingMaskIntoConstraints=NO;[view addSubview:child];
 [NSLayoutConstraint activateConstraints:@[[child.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:18],[child.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-18],[child.topAnchor constraintEqualToAnchor:view.topAnchor constant:16],[child.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-16]]];return view;
}
@implementation ClipboardWindow
-(instancetype)init {
 NSWindow *window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,960,650) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable|NSWindowStyleMaskFullSizeContentView backing:NSBackingStoreBuffered defer:NO];
 self=[super initWithWindow:window];if(!self)return nil;
 self.ids=[NSMutableArray new];self.labels=[NSMutableArray new];window.title=@"共享剪贴板";window.titlebarAppearsTransparent=YES;window.titleVisibility=NSWindowTitleHidden;window.minSize=NSMakeSize(780,540);window.delegate=self;window.releasedWhenClosed=NO;[window center];
 NSVisualEffectView *glass=[NSVisualEffectView new];glass.material=NSVisualEffectMaterialUnderWindowBackground;glass.blendingMode=NSVisualEffectBlendingModeBehindWindow;glass.state=NSVisualEffectStateActive;window.contentView=glass;
 NSTextField *title=label(@"共享剪贴板",25,NSFontWeightSemibold);
 self.statusLabel=label(@"正在连接",12,NSFontWeightRegular);self.statusLabel.textColor=NSColor.secondaryLabelColor;
 NSStackView *heading=stack(@[title,self.statusLabel],NSUserInterfaceLayoutOrientationVertical,8);
 NSButton *sync=[self button:@"同步剪贴板" action:@selector(sync)];NSButton *refresh=[self button:@"刷新" action:@selector(refresh)];NSButton *account=[self button:@"账号" action:@selector(account)];
 NSStackView *buttons=stack(@[sync,refresh,account],NSUserInterfaceLayoutOrientationHorizontal,8);[buttons.widthAnchor constraintEqualToConstant:280].active=YES;
 [heading.widthAnchor constraintGreaterThanOrEqualToConstant:260].active=YES;
 NSStackView *header=stack(@[heading,buttons],NSUserInterfaceLayoutOrientationHorizontal,24);header.alignment=NSLayoutAttributeCenterY;header.distribution=NSStackViewDistributionFill;
 [buttons setHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
 self.table=[NSTableView new];NSTableColumn *column=[[NSTableColumn alloc]initWithIdentifier:@"history"];[self.table addTableColumn:column];self.table.headerView=nil;self.table.rowHeight=76;self.table.intercellSpacing=NSMakeSize(0,6);self.table.delegate=self;self.table.dataSource=self;self.table.target=self;self.table.doubleAction=@selector(duplicate);self.table.backgroundColor=NSColor.clearColor;
 if([self.table respondsToSelector:@selector(setStyle:)])self.table.style=NSTableViewStyleSourceList;
 NSScrollView *history=[NSScrollView new];history.documentView=self.table;history.hasVerticalScroller=YES;history.drawsBackground=NO;
 self.countLabel=label(@"最近记录 · 0",13,NSFontWeightSemibold);
 NSStackView *historyStack=stack(@[self.countLabel,history],NSUserInterfaceLayoutOrientationVertical,14);[history.widthAnchor constraintEqualToAnchor:historyStack.widthAnchor].active=YES;
 NSView *historyCard=card(historyStack);[historyCard.widthAnchor constraintEqualToConstant:310].active=YES;
 self.text=[NSTextView new];self.text.editable=NO;self.text.selectable=YES;self.text.drawsBackground=NO;self.text.font=[NSFont systemFontOfSize:15];self.text.textColor=NSColor.labelColor;self.text.textContainerInset=NSMakeSize(6,10);self.text.autoresizingMask=NSViewWidthSizable;self.text.textContainer.widthTracksTextView=YES;self.text.verticallyResizable=YES;self.text.horizontallyResizable=NO;self.text.string=@"选择左侧记录，查看完整内容。";
 NSScrollView *content=[NSScrollView new];content.hasVerticalScroller=YES;content.drawsBackground=NO;content.documentView=self.text;
 self.image=[NSImageView new];self.image.imageScaling=NSImageScaleProportionallyUpOrDown;self.image.hidden=YES;[self.image.heightAnchor constraintEqualToConstant:210].active=YES;
 self.duplicateButton=[self button:@"复制内容" action:@selector(duplicate)];self.duplicateButton.enabled=NO;[self.duplicateButton.widthAnchor constraintEqualToConstant:100].active=YES;
 NSStackView *previewHeader=stack(@[label(@"内容预览",13,NSFontWeightSemibold),self.duplicateButton],NSUserInterfaceLayoutOrientationHorizontal,18);previewHeader.distribution=NSStackViewDistributionFill;
 NSStackView *previewStack=stack(@[previewHeader,content,self.image],NSUserInterfaceLayoutOrientationVertical,12);
 for(NSView *v in @[previewHeader,content,self.image])[v.widthAnchor constraintEqualToAnchor:previewStack.widthAnchor].active=YES;
 NSView *previewCard=card(previewStack);[previewCard.widthAnchor constraintGreaterThanOrEqualToConstant:360].active=YES;
 NSStackView *panes=stack(@[historyCard,previewCard],NSUserInterfaceLayoutOrientationHorizontal,18);panes.alignment=NSLayoutAttributeTop;[previewCard.widthAnchor constraintEqualToAnchor:panes.widthAnchor constant:-328].active=YES;
 [historyCard.heightAnchor constraintEqualToAnchor:panes.heightAnchor].active=YES;[previewCard.heightAnchor constraintEqualToAnchor:panes.heightAnchor].active=YES;
 NSTextField *hint=label(@"双击记录即可复制 · 关闭窗口后继续同步",11,NSFontWeightRegular);hint.textColor=NSColor.secondaryLabelColor;
 NSButton *unlock=[self button:@"解锁旧记录" action:@selector(unlock)];NSStackView *footer=stack(@[hint,unlock],NSUserInterfaceLayoutOrientationHorizontal,20);footer.distribution=NSStackViewDistributionFill;footer.alignment=NSLayoutAttributeCenterY;[unlock.widthAnchor constraintEqualToConstant:110].active=YES;
 NSStackView *root=stack(@[header,panes,footer],NSUserInterfaceLayoutOrientationVertical,22);[glass addSubview:root];
 for(NSView *v in @[header,panes,footer])[v.widthAnchor constraintEqualToAnchor:root.widthAnchor].active=YES;
 [NSLayoutConstraint activateConstraints:@[[root.leadingAnchor constraintEqualToAnchor:glass.leadingAnchor constant:26],[root.trailingAnchor constraintEqualToAnchor:glass.trailingAnchor constant:-26],[root.topAnchor constraintEqualToAnchor:glass.topAnchor constant:52],[root.bottomAnchor constraintEqualToAnchor:glass.bottomAnchor constant:-20]]];
 return self;
}
-(NSButton*)button:(NSString*)title action:(SEL)action {NSButton *b=[NSButton buttonWithTitle:title target:self action:action];b.bezelStyle=NSBezelStyleRounded;return b;}
-(void)account{[NSApp.delegate performSelector:@selector(login)];}
-(void)unlock{[NSApp.delegate performSelector:@selector(unlock)];}
-(void)sync{if(self.loggedIn)sc_event(2,"");else [self account];}
-(void)refresh{if(self.loggedIn){self.statusLabel.stringValue=@"正在读取历史记录…";sc_event(5,"");}else [self status:@"请先登录，同一账号的记录会显示在这里"];}
-(void)duplicate{NSInteger i=self.table.selectedRow;if(self.duplicateButton.enabled&&i>=0&&i<(NSInteger)self.ids.count)sc_event(6,self.ids[i].UTF8String);}
-(void)open{[NSApp activateIgnoringOtherApps:YES];[self.window makeKeyAndOrderFront:nil];sc_event(13,"1");[self refresh];}
-(BOOL)windowShouldClose:(NSWindow*)window{[window orderOut:nil];sc_event(13,"0");sc_event(9,"");[self clear];return NO;}
-(void)status:(NSString*)value{self.connectionState=value;self.statusLabel.stringValue=value;}
-(void)beginHistory{NSInteger i=self.table.selectedRow;self.selectedId=i>=0&&i<(NSInteger)self.ids.count?self.ids[i]:@"";self.loading=YES;[self.ids removeAllObjects];[self.labels removeAllObjects];self.duplicateButton.enabled=NO;}
-(void)addId:(NSString*)identifier label:(NSString*)value{if(self.window.visible){[self.ids addObject:identifier];[self.labels addObject:value];}}
-(void)endHistory{
 self.statusLabel.stringValue=self.connectionState?:@"历史已更新";
 self.loading=NO;[self.table reloadData];self.countLabel.stringValue=[NSString stringWithFormat:@"最近记录 · %lu",(unsigned long)self.ids.count];
 if(!self.ids.count){self.text.string=@"暂无记录。登录同一账号后，在任一设备复制内容。";self.image.image=nil;self.image.hidden=YES;return;}
 NSUInteger row=[self.ids indexOfObject:self.selectedId];if(row==NSNotFound)row=0;[self.table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];[self tableViewSelectionDidChange:[NSNotification notificationWithName:NSTableViewSelectionDidChangeNotification object:self.table]];
}
-(void)clear{self.loading=YES;[self.ids removeAllObjects];[self.labels removeAllObjects];[self.table reloadData];self.loading=NO;self.selectedId=@"";self.duplicateButton.enabled=NO;self.text.string=@"选择左侧记录，查看完整内容。";self.image.image=nil;self.image.hidden=YES;self.countLabel.stringValue=@"最近记录 · 0";}
-(NSInteger)numberOfRowsInTableView:(NSTableView*)table{return self.labels.count;}
-(NSView*)tableView:(NSTableView*)table viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row{
 NSString *value=self.labels[row];NSRange split=[value rangeOfString:@"  "];NSString *device=split.location==NSNotFound?@"剪贴板":[value substringToIndex:split.location];NSString *preview=split.location==NSNotFound?value:[value substringFromIndex:split.location+2];
 NSTextField *meta=label(device,11,NSFontWeightRegular);meta.textColor=NSColor.secondaryLabelColor;NSTextField *body=label(preview,14,NSFontWeightMedium);
 NSStackView *view=stack(@[meta,body],NSUserInterfaceLayoutOrientationVertical,7);view.edgeInsets=NSEdgeInsetsMake(12,8,10,8);for(NSView *v in @[meta,body])[v.widthAnchor constraintEqualToAnchor:view.widthAnchor constant:-16].active=YES;return view;
}
-(void)tableViewSelectionDidChange:(NSNotification*)note{if(self.loading)return;NSInteger i=self.table.selectedRow;if(i<0||i>=(NSInteger)self.ids.count)return;self.duplicateButton.enabled=NO;self.image.image=nil;self.image.hidden=YES;self.text.string=@"正在读取内容…";sc_event(12,self.ids[i].UTF8String);}
-(void)detailId:(NSString*)identifier text:(NSString*)value image:(NSData*)bytes success:(BOOL)success{
 NSInteger i=self.table.selectedRow;if(!self.window.visible||i<0||i>=(NSInteger)self.ids.count||![self.ids[i] isEqualToString:identifier])return;
 self.text.string=value;self.image.image=bytes.length?[[NSImage alloc]initWithData:bytes]:nil;self.image.hidden=!self.image.image;self.duplicateButton.enabled=success;
}
@end
