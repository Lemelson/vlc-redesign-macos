/* Copyright (C) 2026 VLC Redesign contributors. GPL-2.0-or-later. */
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#import <Cocoa/Cocoa.h>
#import "MXRDialogServices.h"
#import "MXRBridgeKeys.h"
#include <vlc_dialog.h>
#include <vlc_extensions.h>
static NSString *DS(const char *s) { return s?([NSString stringWithUTF8String:s]?:@""):@""; }
@interface MXRDialogRecord : NSObject
@property(nonatomic) vlc_dialog_id *engineID;
@property(nonatomic) uint64_t identifier;
@property(nonatomic,copy) NSDictionary *values;
@end
@implementation MXRDialogRecord
@end
@interface MXRDialogServices ()
- (void)display:(vlc_dialog_id *)identifier values:(NSDictionary *)values;
- (void)cancel:(vlc_dialog_id *)identifier;
- (void)progress:(vlc_dialog_id *)identifier position:(float)position text:(NSString *)text;
@end
static void Login(void *data,vlc_dialog_id *id,const char *title,const char *text,const char *username,bool store) {
    [(__bridge MXRDialogServices *)data display:id values:@{@"kind":@"login",@"title":DS(title),@"text":DS(text),@"defaultUsername":DS(username),@"canStore":@(store)}];
}
static void Question(void *data,vlc_dialog_id *id,const char *title,const char *text,vlc_dialog_question_type type,const char *cancel,const char *action1,const char *action2) {
    NSMutableDictionary *values=[@{@"kind":@"question",@"title":DS(title),@"text":DS(text),@"severity":type==VLC_DIALOG_QUESTION_CRITICAL?@"critical":type==VLC_DIALOG_QUESTION_WARNING?@"warning":@"normal"} mutableCopy];
    if(cancel) values[@"cancel"]=DS(cancel); if(action1) values[@"action1"]=DS(action1); if(action2) values[@"action2"]=DS(action2);
    [(__bridge MXRDialogServices *)data display:id values:values];
}
static void Progress(void *data,vlc_dialog_id *id,const char *title,const char *text,bool indeterminate,float position,const char *cancel) {
    NSMutableDictionary *values=[@{@"kind":@"progress",@"title":DS(title),@"text":DS(text),@"isIndeterminate":@(indeterminate),@"value":@(position)} mutableCopy];
    if(cancel) values[@"cancel"]=DS(cancel); [(__bridge MXRDialogServices *)data display:id values:values];
}
static void Cancel(void *data,vlc_dialog_id *id) { [(__bridge MXRDialogServices *)data cancel:id]; }
static void Update(void *data,vlc_dialog_id *id,float position,const char *text) { [(__bridge MXRDialogServices *)data progress:id position:position text:DS(text)]; }
static void DisplayError(void *data,const char *title,const char *text) { [(__bridge MXRDialogServices *)data display:NULL values:@{@"kind":@"error",@"title":DS(title),@"text":DS(text)}]; }
static const vlc_dialog_cbs DialogCallbacks={.pf_display_login=Login,.pf_display_question=Question,.pf_display_progress=Progress,.pf_cancel=Cancel,.pf_update_progress=Update};

#pragma mark - Lua extension dialogs

/* A Lua extension (VLsub, ...) builds its own form: vlc.dialog() plus labels, fields, buttons,
 * lists on a grid (include/vlc_extensions.h). The Lua thread hands the dialog over through
 * vlc_ext_dialog_update and, when it deletes the dialog or a widget, waits until the UI has
 * let go of it (p_sys_intf == NULL, modules/lua/libs/dialog.c).
 *
 * Unlike the stock interface, which hops synchronously to the main thread here, this provider
 * answers that protocol on the calling thread: it marks what it holds, releases what was
 * killed, snapshots the form and lets the main thread draw the snapshot later. The Lua thread
 * therefore never waits for the main thread, so quitting or reloading extensions while a
 * dialog is open cannot deadlock. Each dialog and widget gets a serial number (stored as its
 * p_sys_intf); the main thread reaches an engine widget only through that registry, under
 * the registry lock, so it never touches one the extension has freed. */
@class MXRExtensionDialogWindow;
@interface MXRDialogServices ()
- (void)extensionDialogChanged:(extension_dialog_t *)dialog;
- (void)extensionDialog:(NSNumber *)dialogID widget:(nullable NSNumber *)widgetID
                perform:(void (^)(extension_dialog_t *dialog, extension_widget_t *_Nullable widget))block;
- (void)extensionDialogClosed:(NSNumber *)dialogID;
@end

static void ExtensionDialogUpdate(extension_dialog_t *dialog, void *data) {
    @autoreleasepool { [(__bridge MXRDialogServices *)data extensionDialogChanged:dialog]; }
}

/* Labels and HTML areas carry rich text; drawn in the system font and label colour. */
static NSAttributedString *ExtensionRichText(NSString *text, CGFloat size) {
    NSFont *base = [NSFont systemFontOfSize:size];
    if ([text rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"<&"]].location == NSNotFound)
        return [[NSAttributedString alloc] initWithString:text attributes:@{NSFontAttributeName:base, NSForegroundColorAttributeName:NSColor.labelColor}];
    NSData *data = [[@"<meta charset=\"utf-8\">" stringByAppendingString:text] dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableAttributedString *rich = [[NSMutableAttributedString alloc] initWithHTML:data documentAttributes:NULL];
    if (rich == nil) return [[NSAttributedString alloc] initWithString:text attributes:@{NSFontAttributeName:base}];
    NSRange all = NSMakeRange(0, rich.length);
    [rich enumerateAttribute:NSFontAttributeName inRange:all options:0 usingBlock:^(NSFont *font, NSRange range, BOOL *stop) {
        NSFontDescriptorSymbolicTraits traits = font.fontDescriptor.symbolicTraits & (NSFontDescriptorTraitBold | NSFontDescriptorTraitItalic);
        NSFont *mapped = [NSFont fontWithDescriptor:[base.fontDescriptor fontDescriptorWithSymbolicTraits:traits] size:size] ?: base;
        [rich addAttribute:NSFontAttributeName value:mapped range:range];
    }];
    [rich addAttribute:NSForegroundColorAttributeName value:NSColor.labelColor range:all];
    while (rich.length > 0 && [NSCharacterSet.newlineCharacterSet characterIsMember:[rich.string characterAtIndex:rich.length - 1]])
        [rich deleteCharactersInRange:NSMakeRange(rich.length - 1, 1)];
    return rich;
}

/* A list widget: one text column, multiple selection. */
@interface MXRExtensionList : NSObject <NSTableViewDataSource, NSTableViewDelegate>
@property(nonatomic, copy) NSArray<NSDictionary *> *values;
@property(nonatomic, copy) void (^selectionChanged)(NSIndexSet *rows);
@end
@implementation MXRExtensionList
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return (NSInteger)self.values.count; }
- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row { return self.values[(NSUInteger)row][@"text"]; }
- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (self.selectionChanged) self.selectionChanged([(NSTableView *)notification.object selectedRowIndexes]);
}
@end

/* One extension dialog: a native window with the script's widgets on an NSGridView. Main thread. */
@interface MXRExtensionDialogWindow : NSObject <NSWindowDelegate>
- (instancetype)initWithServices:(MXRDialogServices *)services dialogID:(NSNumber *)dialogID;
- (void)apply:(NSDictionary *)state;
- (void)close;
@end
@implementation MXRExtensionDialogWindow {
    __weak MXRDialogServices *_services;
    NSNumber *_dialogID;
    NSWindow *_window;
    NSMutableDictionary<NSNumber *, NSView *> *_views;       /* widget id -> control (outer view) */
    NSMutableDictionary<NSNumber *, NSControl *> *_controls; /* widget id -> the control itself */
    NSMutableDictionary<NSNumber *, MXRExtensionList *> *_lists;
    NSArray *_layout;
    BOOL _shown;
}
- (instancetype)initWithServices:(MXRDialogServices *)services dialogID:(NSNumber *)dialogID {
    if (!(self = [super init])) return nil;
    _services = services; _dialogID = dialogID;
    _views = [NSMutableDictionary dictionary]; _controls = [NSMutableDictionary dictionary]; _lists = [NSMutableDictionary dictionary];
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 360, 120)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:YES];
    _window.releasedWhenClosed = NO;
    _window.delegate = self;
    _window.contentView = [NSView new];
    return self;
}
- (void)close { _window.delegate = nil; [_window orderOut:nil]; }
- (BOOL)windowShouldClose:(NSWindow *)sender {
    [_services extensionDialogClosed:_dialogID];
    [_window orderOut:nil]; _shown = NO;
    return NO; /* the extension decides: it usually deletes the dialog, or shows it again */
}

- (void)write:(NSNumber *)widgetID with:(void (^)(extension_dialog_t *, extension_widget_t *))block {
    [_services extensionDialog:_dialogID widget:widgetID perform:^(extension_dialog_t *dialog, extension_widget_t *widget) { if (widget) block(dialog, widget); }];
}
- (void)buttonPressed:(NSButton *)button {
    NSNumber *widgetID = @(button.tag);
    BOOL checked = button.state == NSControlStateValueOn;
    [self write:widgetID with:^(extension_dialog_t *dialog, extension_widget_t *widget) {
        if (widget->type == EXTENSION_WIDGET_CHECK_BOX) widget->b_checked = checked;
        else extension_WidgetClicked(dialog, widget);
    }];
}
- (void)popUpChanged:(NSPopUpButton *)popup {
    NSInteger index = popup.indexOfSelectedItem;
    [self write:@(popup.tag) with:^(extension_dialog_t *dialog, extension_widget_t *widget) {
        NSInteger i = 0;
        for (struct extension_widget_value_t *value = widget->p_values; value != NULL; value = value->p_next, i++) value->b_selected = i == index;
    }];
}
- (void)textChanged:(NSNotification *)notification {
    NSTextField *field = notification.object;
    NSString *text = field.stringValue;
    [self write:@(field.tag) with:^(extension_dialog_t *dialog, extension_widget_t *widget) {
        free(widget->psz_text); widget->psz_text = strdup(text.UTF8String);
    }];
}

- (NSView *)makeView:(NSDictionary *)widget {
    NSInteger tag = [widget[@"id"] integerValue];
    switch ((extension_widget_type_e)[widget[@"type"] intValue]) {
        case EXTENSION_WIDGET_LABEL: {
            NSTextField *label = [NSTextField wrappingLabelWithString:@""];
            label.selectable = YES; label.allowsEditingTextAttributes = YES;
            label.preferredMaxLayoutWidth = 480;
            _controls[@(tag)] = label; return label;
        }
        case EXTENSION_WIDGET_BUTTON: {
            NSButton *button = [NSButton buttonWithTitle:@"" target:self action:@selector(buttonPressed:)];
            button.tag = tag; _controls[@(tag)] = button; return button;
        }
        case EXTENSION_WIDGET_CHECK_BOX: {
            NSButton *box = [NSButton checkboxWithTitle:@"" target:self action:@selector(buttonPressed:)];
            box.tag = tag; _controls[@(tag)] = box; return box;
        }
        case EXTENSION_WIDGET_TEXT_FIELD:
        case EXTENSION_WIDGET_PASSWORD: {
            NSTextField *field = [widget[@"type"] intValue] == EXTENSION_WIDGET_PASSWORD ? [NSSecureTextField new] : [NSTextField new];
            field.tag = tag;
            [field.widthAnchor constraintGreaterThanOrEqualToConstant:MAX(160, [widget[@"width"] doubleValue])].active = YES;
            [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(textChanged:) name:NSControlTextDidChangeNotification object:field];
            _controls[@(tag)] = field; return field;
        }
        case EXTENSION_WIDGET_DROPDOWN: {
            NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
            popup.tag = tag; popup.target = self; popup.action = @selector(popUpChanged:);
            _controls[@(tag)] = popup; return popup;
        }
        case EXTENSION_WIDGET_LIST: {
            NSTableView *table = [NSTableView new];
            NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"text"];
            column.resizingMask = NSTableColumnAutoresizingMask;
            [table addTableColumn:column];
            table.headerView = nil; table.allowsMultipleSelection = YES; table.usesAlternatingRowBackgroundColors = YES;
            table.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
            MXRExtensionList *list = [MXRExtensionList new];
            __weak MXRExtensionDialogWindow *weakSelf = self;
            list.selectionChanged = ^(NSIndexSet *rows) {
                [weakSelf write:@(tag) with:^(extension_dialog_t *dialog, extension_widget_t *engine) {
                    NSUInteger i = 0;
                    for (struct extension_widget_value_t *value = engine->p_values; value != NULL; value = value->p_next, i++) value->b_selected = [rows containsIndex:i];
                }];
            };
            table.dataSource = list; table.delegate = list; _lists[@(tag)] = list;
            NSScrollView *scroll = [NSScrollView new];
            scroll.documentView = table; scroll.hasVerticalScroller = YES; scroll.borderType = NSBezelBorder;
            [scroll.widthAnchor constraintGreaterThanOrEqualToConstant:MAX(240, [widget[@"width"] doubleValue])].active = YES;
            [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:MAX(120, [widget[@"height"] doubleValue])].active = YES;
            return scroll;
        }
        case EXTENSION_WIDGET_HTML: {
            NSScrollView *scroll = [NSTextView scrollableTextView];
            NSTextView *text = scroll.documentView;
            text.editable = NO; text.selectable = YES; text.drawsBackground = NO;
            scroll.drawsBackground = NO;
            [scroll.widthAnchor constraintGreaterThanOrEqualToConstant:MAX(320, [widget[@"width"] doubleValue])].active = YES;
            [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:MAX(160, [widget[@"height"] doubleValue])].active = YES;
            return scroll;
        }
        case EXTENSION_WIDGET_IMAGE: {
            NSImageView *image = [NSImageView new];
            image.imageScaling = NSImageScaleProportionallyUpOrDown;
            return image;
        }
        case EXTENSION_WIDGET_SPIN_ICON: {
            NSProgressIndicator *spinner = [NSProgressIndicator new];
            spinner.style = NSProgressIndicatorStyleSpinning; spinner.controlSize = NSControlSizeSmall;
            spinner.displayedWhenStopped = NO;
            return spinner;
        }
    }
    return nil;
}

- (void)update:(NSView *)view with:(NSDictionary *)widget {
    NSString *text = widget[@"text"];
    NSArray<NSDictionary *> *values = widget[@"values"];
    switch ((extension_widget_type_e)[widget[@"type"] intValue]) {
        case EXTENSION_WIDGET_LABEL: ((NSTextField *)view).attributedStringValue = ExtensionRichText(text, NSFont.systemFontSize); break;
        case EXTENSION_WIDGET_BUTTON: ((NSButton *)view).title = text; break;
        case EXTENSION_WIDGET_CHECK_BOX:
            ((NSButton *)view).title = text;
            ((NSButton *)view).state = [widget[@"checked"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff; break;
        case EXTENSION_WIDGET_TEXT_FIELD:
        case EXTENSION_WIDGET_PASSWORD: ((NSTextField *)view).stringValue = text; break;
        case EXTENSION_WIDGET_DROPDOWN: {
            NSPopUpButton *popup = (NSPopUpButton *)view;
            [popup removeAllItems];
            NSInteger selected = -1;
            for (NSDictionary *value in values) {
                [popup.menu addItemWithTitle:value[@"text"] action:nil keyEquivalent:@""];
                if ([value[@"selected"] boolValue] && selected < 0) selected = popup.numberOfItems - 1;
            }
            if (popup.numberOfItems > 0) { [popup selectItemAtIndex:MAX(0, selected)]; if (selected < 0) [self popUpChanged:popup]; }
            break;
        }
        case EXTENSION_WIDGET_LIST: {
            NSTableView *table = ((NSScrollView *)view).documentView;
            MXRExtensionList *list = _lists[widget[@"id"]];
            void (^changed)(NSIndexSet *) = list.selectionChanged;
            list.selectionChanged = nil; /* reflecting the engine's selection is not a user change */
            list.values = values; [table reloadData];
            NSMutableIndexSet *rows = [NSMutableIndexSet indexSet];
            [values enumerateObjectsUsingBlock:^(NSDictionary *value, NSUInteger i, BOOL *stop) { if ([value[@"selected"] boolValue]) [rows addIndex:i]; }];
            [table selectRowIndexes:rows byExtendingSelection:NO];
            list.selectionChanged = changed;
            break;
        }
        case EXTENSION_WIDGET_HTML: {
            NSTextView *textView = ((NSScrollView *)view).documentView;
            [textView.textStorage setAttributedString:ExtensionRichText(text, NSFont.systemFontSize)];
            break;
        }
        case EXTENSION_WIDGET_IMAGE:
            ((NSImageView *)view).image = text.length > 0 ? [[NSImage alloc] initWithContentsOfFile:text] : nil; break;
        case EXTENSION_WIDGET_SPIN_ICON:
            if ([widget[@"spinning"] boolValue]) [(NSProgressIndicator *)view startAnimation:nil];
            else [(NSProgressIndicator *)view stopAnimation:nil];
            break;
    }
}

/* Positions as Qt's provider does: rows and columns are 1-based; a widget without a row goes
 * below the others. Overlapping spans are not merged (NSGridView would throw). */
- (void)layoutWidgets:(NSArray<NSDictionary *> *)widgets {
    NSView *focused = [_window.firstResponder isKindOfClass:NSView.class] ? (NSView *)_window.firstResponder : nil;
    for (NSView *view in _window.contentView.subviews.copy) [view removeFromSuperview];
    NSMutableArray *placed = [NSMutableArray array];
    NSInteger rows = 0, columns = 1;
    for (NSDictionary *widget in widgets) {
        NSInteger row = [widget[@"row"] integerValue] - 1, column = [widget[@"column"] integerValue] - 1;
        if (row < 0) { row = rows; column = 0; }
        NSInteger height = MAX(1, [widget[@"vspan"] integerValue]), width = MAX(1, [widget[@"hspan"] integerValue]);
        rows = MAX(rows, row + height); columns = MAX(columns, MAX(0, column) + width);
        [placed addObject:@[widget[@"id"], @(row), @(MAX(0, column)), @(width), @(height)]];
    }
    if (rows == 0) return;
    NSGridView *grid = [NSGridView gridViewWithNumberOfColumns:columns rows:rows];
    grid.rowSpacing = 8; grid.columnSpacing = 8; grid.rowAlignment = NSGridRowAlignmentFirstBaseline;
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    NSMutableSet<NSIndexPath *> *used = [NSMutableSet set];
    for (NSArray *entry in placed) {
        NSView *view = _views[entry[0]];
        NSInteger row = [entry[1] integerValue], column = [entry[2] integerValue], width = [entry[3] integerValue], height = [entry[4] integerValue];
        NSIndexPath *head = [NSIndexPath indexPathForItem:column inSection:row];
        if (view == nil || [used containsObject:head]) continue;
        [grid cellAtColumnIndex:column rowIndex:row].contentView = view;
        BOOL free = YES;
        for (NSInteger r = row; r < row + height; r++)
            for (NSInteger c = column; c < column + width; c++)
                free &= ![used containsObject:[NSIndexPath indexPathForItem:c inSection:r]];
        for (NSInteger r = row; r < row + (free ? height : 1); r++)
            for (NSInteger c = column; c < column + (free ? width : 1); c++)
                [used addObject:[NSIndexPath indexPathForItem:c inSection:r]];
        if (free && (width > 1 || height > 1))
            [grid mergeCellsInHorizontalRange:NSMakeRange((NSUInteger)column, (NSUInteger)width) verticalRange:NSMakeRange((NSUInteger)row, (NSUInteger)height)];
    }
    NSView *content = _window.contentView;
    [content addSubview:grid];
    [NSLayoutConstraint activateConstraints:@[
        [grid.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:20],
        [grid.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-20],
        [grid.topAnchor constraintEqualToAnchor:content.topAnchor constant:20],
        [grid.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20]]];
    if (focused != nil && [focused isDescendantOf:content]) [_window makeFirstResponder:focused];
}

- (void)apply:(NSDictionary *)state {
    _window.title = state[@"title"];
    NSArray<NSDictionary *> *widgets = state[@"widgets"];
    NSMutableSet *alive = [NSMutableSet set];
    NSMutableArray *layout = [NSMutableArray array];
    for (NSDictionary *widget in widgets) {
        NSNumber *widgetID = widget[@"id"];
        [alive addObject:widgetID];
        NSView *view = _views[widgetID];
        BOOL created = view == nil;
        if (created) { view = [self makeView:widget]; if (view == nil) continue; _views[widgetID] = view; }
        NSView *control = _controls[widgetID] ?: view;
        if (created || [widget[@"update"] boolValue]) [self update:control with:widget];
        view.hidden = [widget[@"hidden"] boolValue];
        [layout addObject:@[widgetID, widget[@"row"], widget[@"column"], widget[@"hspan"], widget[@"vspan"]]];
    }
    for (NSNumber *widgetID in _views.allKeys) if (![alive containsObject:widgetID]) {
        NSControl *control = _controls[widgetID];
        if (control) [NSNotificationCenter.defaultCenter removeObserver:self name:NSControlTextDidChangeNotification object:control];
        [_views removeObjectForKey:widgetID]; [_controls removeObjectForKey:widgetID]; [_lists removeObjectForKey:widgetID];
    }
    if (![layout isEqual:_layout]) { _layout = layout; [self layoutWidgets:widgets]; }
    if ([state[@"hidden"] boolValue]) { [_window orderOut:nil]; _shown = NO; return; }
    if (!_shown) {
        NSSize fitting = _window.contentView.fittingSize;
        NSSize hint = NSMakeSize([state[@"width"] doubleValue], [state[@"height"] doubleValue]);
        [_window setContentSize:NSMakeSize(MAX(fitting.width, hint.width), MAX(fitting.height, hint.height))];
        _window.contentMinSize = fitting;
        [_window center];
        [_window makeKeyAndOrderFront:nil];
        _shown = YES;
    }
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
@end
@implementation MXRDialogServices {
    intf_thread_t *_intf;
    NSLock *_lock;
    NSMutableArray<MXRDialogRecord *> *_records;
    uint64_t _nextID;
    BOOL _stopped;
    /* Extension dialogs. _extLock guards the registry and the serials; it is taken inside
     * the provider's lock (engine callback) and before a dialog's own lock. */
    vlc_mutex_t _extLock;
    NSMutableDictionary<NSNumber *, NSValue *> *_extDialogs; /* serial -> extension_dialog_t * */
    NSMutableDictionary<NSNumber *, NSValue *> *_extWidgets; /* serial -> extension_widget_t * */
    uintptr_t _extSerial;
    BOOL _extStopped;                                         /* under _extLock */
    NSMutableDictionary<NSNumber *, MXRExtensionDialogWindow *> *_extWindows; /* main thread */
}
- (instancetype)initWithInterface:(intf_thread_t *)intf {
    if(!(self=[super init])) return nil;
    _intf=intf; _lock=[NSLock new]; _records=[NSMutableArray array];
    vlc_dialog_provider_set_callbacks(intf,&DialogCallbacks,(__bridge void *)self);
    vlc_dialog_provider_set_error_callback(intf,DisplayError,(__bridge void *)self);
    vlc_mutex_init(&_extLock);
    _extDialogs=[NSMutableDictionary dictionary]; _extWidgets=[NSMutableDictionary dictionary]; _extWindows=[NSMutableDictionary dictionary];
    vlc_dialog_provider_set_ext_callback(intf,ExtensionDialogUpdate,(__bridge void *)self);
    return self;
}
- (void)notify {
    __weak MXRDialogServices *weakSelf=self;
    dispatch_async(dispatch_get_main_queue(),^{ MXRDialogServices *self=weakSelf; if(self && !self->_stopped && self.serviceChanged) self.serviceChanged(MXRBridgeServiceDialogs); });
}
- (void)display:(vlc_dialog_id *)identifier values:(NSDictionary *)values {
    MXRDialogRecord *record=[MXRDialogRecord new]; record.engineID=identifier;
    [_lock lock];
    if(_stopped) { [_lock unlock]; if(identifier) vlc_dialog_id_dismiss(identifier); return; }
    record.identifier=++_nextID; NSMutableDictionary *d=[values mutableCopy]; d[@"id"]=@(record.identifier); record.values=d;
    [_records addObject:record]; [_lock unlock]; [self notify];
}
- (MXRDialogRecord *)recordForEngineID:(vlc_dialog_id *)identifier {
    for(MXRDialogRecord *r in _records) if(r.engineID==identifier) return r; return nil;
}
- (void)cancel:(vlc_dialog_id *)identifier {
    [_lock lock]; MXRDialogRecord *record=[self recordForEngineID:identifier];
    vlc_dialog_id *engine=record.engineID; record.engineID=NULL;
    if(record) [_records removeObject:record]; [_lock unlock];
    if(engine) vlc_dialog_id_dismiss(engine); [self notify];
}
- (void)progress:(vlc_dialog_id *)identifier position:(float)position text:(NSString *)text {
    [_lock lock]; MXRDialogRecord *record=[self recordForEngineID:identifier];
    if(record) { NSMutableDictionary *d=[record.values mutableCopy]; d[@"value"]=@(position); d[@"text"]=text; record.values=d; }
    [_lock unlock]; [self notify];
}
- (NSDictionary *)snapshot {
    [_lock lock]; NSMutableArray *result=[NSMutableArray array]; for(MXRDialogRecord *r in _records) [result addObject:[r.values copy]]; [_lock unlock];
    return @{@"dialogs":result,@"requests":result};
}
- (BOOL)performCommand:(MXRBridgeCommand)command arguments:(NSDictionary *)args error:(NSError **)error {
    uint64_t id=[args[@"id"] unsignedLongLongValue]; [_lock lock]; MXRDialogRecord *record=nil;
    for(MXRDialogRecord *r in _records) if(r.identifier==id) { record=r; break; }
    BOOL supported=[command isEqual:MXRBridgeCommandPostLogin]||[command isEqual:MXRBridgeCommandPostAction]||[command isEqual:MXRBridgeCommandDismiss];
    if(!record||!supported||_stopped) { [_lock unlock]; if(error) *error=[NSError errorWithDomain:@"MXRVLCBridge" code:5 userInfo:@{NSLocalizedDescriptionKey:@"This dialog is no longer available."}]; return NO; }
    NSString *kind=record.values[@"kind"]; NSInteger action=[args[@"action"] integerValue];
    BOOL valid=[command isEqual:MXRBridgeCommandDismiss] || ([command isEqual:MXRBridgeCommandPostLogin]&&[kind isEqual:@"login"]&&[args[@"username"] isKindOfClass:NSString.class]&&[args[@"password"] isKindOfClass:NSString.class]) || ([command isEqual:MXRBridgeCommandPostAction]&&[kind isEqual:@"question"]&&(action==1||action==2)&&record.values[action==1?@"action1":@"action2"]!=nil);
    if(!valid) { [_lock unlock]; if(error) *error=[NSError errorWithDomain:@"MXRVLCBridge" code:5 userInfo:@{NSLocalizedDescriptionKey:@"The answer does not match this dialog."}]; return NO; }
    vlc_dialog_id *engine=record.engineID; record.engineID=NULL; [_records removeObject:record]; [_lock unlock];
    int ret=VLC_SUCCESS;
    if(engine) {
        if([command isEqual:MXRBridgeCommandPostLogin]) ret=vlc_dialog_id_post_login(engine,[args[@"username"] UTF8String],[args[@"password"] UTF8String],[args[@"store"] boolValue]);
        else if([command isEqual:MXRBridgeCommandPostAction]) ret=vlc_dialog_id_post_action(engine,[args[@"action"] intValue]);
        else ret=vlc_dialog_id_dismiss(engine);
    }
    [self notify];
    if(ret!=VLC_SUCCESS && error) *error=[NSError errorWithDomain:@"MXRVLCBridge" code:5 userInfo:@{NSLocalizedDescriptionKey:@"VLC rejected the dialog answer."}];
    return ret==VLC_SUCCESS;
}
#pragma mark Extension dialogs

/* Under _extLock and the dialog's lock: the UI holds nothing of it any more. */
- (void)releaseExtensionDialog:(extension_dialog_t *)dialog {
    extension_widget_t *widget;
    ARRAY_FOREACH(widget, dialog->widgets) {
        if (widget == NULL || widget->p_sys_intf == NULL) continue;
        [_extWidgets removeObjectForKey:@((uintptr_t)widget->p_sys_intf)];
        widget->p_sys_intf = NULL;
    }
    if (dialog->p_sys_intf != NULL) [_extDialogs removeObjectForKey:@((uintptr_t)dialog->p_sys_intf)];
    dialog->p_sys_intf = NULL;
}

static NSDictionary *ExtensionWidgetState(extension_widget_t *widget, NSNumber *identifier, BOOL update) {
    NSMutableArray *values = [NSMutableArray array];
    for (struct extension_widget_value_t *value = widget->p_values; value != NULL; value = value->p_next)
        [values addObject:@{@"id":@(value->i_id), @"text":DS(value->psz_text), @"selected":@(value->b_selected)}];
    return @{@"id":identifier, @"type":@(widget->type), @"text":DS(widget->psz_text), @"values":values,
             @"checked":@(widget->b_checked), @"row":@(widget->i_row), @"column":@(widget->i_column),
             @"hspan":@(widget->i_horiz_span), @"vspan":@(widget->i_vert_span), @"width":@(widget->i_width),
             @"height":@(widget->i_height), @"hidden":@(widget->b_hide), @"spinning":@(widget->i_spin_loops != 0), @"update":@(update)};
}

/* Engine thread (the extension's), inside the provider lock. Never waits for main. */
- (void)extensionDialogChanged:(extension_dialog_t *)dialog {
    vlc_mutex_lock(&_extLock);
    vlc_mutex_lock(&dialog->lock);
    NSNumber *dialogID = dialog->p_sys_intf != NULL ? @((uintptr_t)dialog->p_sys_intf) : nil;
    NSDictionary *state = nil;
    if (dialog->b_kill || _extStopped) {
        [self releaseExtensionDialog:dialog];
    } else {
        if (dialogID == nil) {
            dialog->p_sys_intf = (void *)++_extSerial; dialogID = @(_extSerial);
            _extDialogs[dialogID] = [NSValue valueWithPointer:dialog];
        }
        NSMutableArray *widgets = [NSMutableArray array];
        extension_widget_t *widget;
        ARRAY_FOREACH(widget, dialog->widgets) {
            if (widget == NULL) continue;
            if (widget->b_kill) {
                if (widget->p_sys_intf != NULL) [_extWidgets removeObjectForKey:@((uintptr_t)widget->p_sys_intf)];
                widget->p_sys_intf = NULL;
                continue;
            }
            BOOL created = widget->p_sys_intf == NULL;
            if (created) {
                widget->p_sys_intf = (void *)++_extSerial;
                _extWidgets[@(_extSerial)] = [NSValue valueWithPointer:widget];
            }
            [widgets addObject:ExtensionWidgetState(widget, @((uintptr_t)widget->p_sys_intf), created || widget->b_update)];
            widget->b_update = false;
        }
        state = @{@"title":DS(dialog->psz_title), @"width":@(dialog->i_width), @"height":@(dialog->i_height),
                  @"hidden":@(dialog->b_hide), @"widgets":widgets};
    }
    vlc_cond_broadcast(&dialog->cond); /* a deleting extension waits for p_sys_intf == NULL */
    vlc_mutex_unlock(&dialog->lock);
    vlc_mutex_unlock(&_extLock);
    if (dialogID == nil) return;
    __weak MXRDialogServices *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf showExtensionDialog:dialogID state:state]; });
}

/* Main thread. `state` nil closes the window. */
- (void)showExtensionDialog:(NSNumber *)dialogID state:(nullable NSDictionary *)state {
    MXRExtensionDialogWindow *window = _extWindows[dialogID];
    if (state == nil || _stopped) { [window close]; [_extWindows removeObjectForKey:dialogID]; return; }
    if (window == nil) { window = [[MXRExtensionDialogWindow alloc] initWithServices:self dialogID:dialogID]; _extWindows[dialogID] = window; }
    [window apply:state];
}

/* Main thread: runs `block` only while the extension still owns the dialog (and the widget). */
- (void)extensionDialog:(NSNumber *)dialogID widget:(nullable NSNumber *)widgetID
                perform:(void (^)(extension_dialog_t *dialog, extension_widget_t *_Nullable widget))block {
    vlc_mutex_lock(&_extLock);
    extension_dialog_t *dialog = _extDialogs[dialogID].pointerValue;
    extension_widget_t *widget = widgetID != nil ? _extWidgets[widgetID].pointerValue : NULL;
    if (dialog != NULL && (widgetID == nil || (widget != NULL && widget->p_dialog == dialog))) {
        vlc_mutex_lock(&dialog->lock);
        block(dialog, widget);
        vlc_mutex_unlock(&dialog->lock);
    }
    vlc_mutex_unlock(&_extLock);
}

- (void)extensionDialogClosed:(NSNumber *)dialogID {
    vlc_mutex_lock(&_extLock);
    extension_dialog_t *dialog = _extDialogs[dialogID].pointerValue;
    if (dialog != NULL) extension_DialogClosed(dialog); /* queued to the extension's thread */
    vlc_mutex_unlock(&_extLock);
}

- (void)shutdown {
    [_lock lock]; _stopped=YES; [_lock unlock]; _serviceChanged=nil;
    vlc_dialog_provider_set_callbacks(_intf,NULL,NULL); vlc_dialog_provider_set_error_callback(_intf,NULL,NULL);
    /* After this no update reaches us; let go of every dialog so an extension that deletes
     * one while the interface closes (extensions unload later) does not wait for us. */
    vlc_dialog_provider_set_ext_callback(_intf,NULL,NULL);
    vlc_mutex_lock(&_extLock);
    _extStopped=YES;
    for (NSValue *value in _extDialogs.allValues) {
        extension_dialog_t *dialog=value.pointerValue;
        vlc_mutex_lock(&dialog->lock); [self releaseExtensionDialog:dialog]; vlc_cond_broadcast(&dialog->cond); vlc_mutex_unlock(&dialog->lock);
    }
    [_extDialogs removeAllObjects]; [_extWidgets removeAllObjects];
    vlc_mutex_unlock(&_extLock);
    for (MXRExtensionDialogWindow *window in _extWindows.allValues) [window close];
    [_extWindows removeAllObjects];
    [_lock lock]; NSArray *records=[_records copy]; [_records removeAllObjects]; [_lock unlock];
    for(MXRDialogRecord *record in records) { if(record.engineID) vlc_dialog_id_dismiss(record.engineID); record.engineID=NULL; }
}
@end
