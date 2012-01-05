#import "AtomController.h"

#import "JSCocoa.h"
#import <WebKit/WebKit.h>
#import <dispatch/dispatch.h>

#import "AtomApp.h"
#import "FileSystemHelper.h"

@interface AtomController ()
@property (nonatomic, retain) JSCocoa *jscocoa;
@property (nonatomic, retain, readwrite) NSString *url;
@property (nonatomic, retain, readwrite) NSString *bootstrapScript;
@property (nonatomic, retain, readwrite) FileSystemHelper *fs;

- (void)createWebView;
- (void)blockUntilWebViewLoads;

@end

@interface WebView (Atom)
- (id)inspector;
- (void)showConsole:(id)sender;
- (void)startDebuggingJavaScript:(id)sender;
@end

@implementation AtomController

@synthesize webView = _webView; 
@synthesize jscocoa = _jscocoa;
@synthesize url = _url;
@synthesize bootstrapScript = _bootstrapScript;
@synthesize fs = _fs;

- (void)dealloc {
  self.webView = nil;
  self.bootstrapScript = nil;
  self.url = nil;
  self.jscocoa = nil;
  self.fs = nil;

  [super dealloc];
}

- (id)initWithBootstrapScript:(NSString *)bootstrapScript url:(NSString *)url {
  self = [super initWithWindowNibName:@"AtomWindow"];
  self.bootstrapScript = bootstrapScript;
  self.url = url;
  
  [self.window makeKeyWindow];
  return self;
}

- (id)initForSpecs {
  return [self initWithBootstrapScript:@"spec-bootstrap" url:nil];
}

- (id)initWithURL:(NSString *)url {
  return [self initWithBootstrapScript:@"bootstrap" url:url];
}

- (void)windowDidLoad {
  [super windowDidLoad];
  
  [self.window setDelegate:self];
  [self.window setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
  
  [self setShouldCascadeWindows:YES];
  [self setWindowFrameAutosaveName:@"atomController"];
  
  [self createWebView];  
}

- (void)triggerAtomEventWithName:(NSString *)name data:(id)data {
   [self.jscocoa callJSFunctionNamed:@"triggerEvent" withArguments:name, data, false, nil];
}

- (void)createWebView {
  self.webView = [[WebView alloc] initWithFrame:[self.window.contentView frame]];
  
  [self.webView setAutoresizingMask:NSViewWidthSizable|NSViewHeightSizable];
  [self.window.contentView addSubview:self.webView];  
  [self.webView setUIDelegate:self];
  [self.webView setFrameLoadDelegate:self];

  NSURL *resourceDirURL = [[NSBundle mainBundle] resourceURL];
  NSURL *indexURL = [resourceDirURL URLByAppendingPathComponent:@"index.html"];
  
  NSURLRequest *request = [NSURLRequest requestWithURL:indexURL]; 
  [[self.webView mainFrame] loadRequest:request];
  
  [[self.webView inspector] showConsole:self];
  
  [self blockUntilWebViewLoads];
}

- (void)blockUntilWebViewLoads {
  NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
  while (self.webView.isLoading) {
    [runLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
  }
}

- (void)reload {
  [self.webView reload:self];
}

- (void)close {
  [(AtomApp *)NSApp removeController:self]; 
  [super close];  
}

- (NSString *)projectPath {
  return PROJECT_DIR;
}

- (void)performActionForMenuItemPath:(NSString *)menuItemPath {  
  NSString *jsCode = [NSString stringWithFormat:@"window.performActionForMenuItemPath('%@')", menuItemPath];
  [self.jscocoa evalJSString:jsCode];
}

- (JSValueRefAndContextRef)jsWindow {
  JSValueRef window = [self.jscocoa evalJSString:@"window"]; 
  JSValueRefAndContextRef windowWithContext = {window, self.jscocoa.ctx};
  return windowWithContext;
}

- (BOOL)isFile:(NSString *)path {
  BOOL isDir;
  BOOL exists;
  exists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
  return exists && !isDir;
}

- (NSString *)absolute:(NSString *)path {
  path = [path stringByStandardizingPath];
  if ([path characterAtIndex:0] == '/') {
    return path;
  }
    
  NSString *resolvedPath = [[NSFileManager defaultManager] currentDirectoryPath];
  resolvedPath = [[resolvedPath stringByAppendingPathComponent:path] stringByStandardizingPath];
  
  return resolvedPath;
}

#pragma mark NSWindowDelegate
- (BOOL)windowShouldClose:(id)sender {
  [self close];
  return YES;
}

- (void)keyDown:(NSEvent *)event {
  if ([event modifierFlags] & NSCommandKeyMask && [[event charactersIgnoringModifiers] hasPrefix:@"r"]) {
    [self reload];
  }
}

#pragma mark WebUIDelegate
- (NSArray *)webView:(WebView *)sender contextMenuItemsForElement:(NSDictionary *)element defaultMenuItems:(NSArray *)defaultMenuItems {
  return defaultMenuItems;
}

- (void)webViewClose:(WebView *)sender { // Triggered when closed from javascript
  [self close];
}

#pragma mark WebFrameLoadDelegate
- (void)webView:(WebView *)sender didCommitLoadForFrame:(WebFrame *)frame {
  self.jscocoa = [[JSCocoa alloc] initWithGlobalContext:[frame globalContext]];
  [self.jscocoa setObject:self withName:@"$atomController"];
  [self.jscocoa setObject:self.bootstrapScript withName:@"$bootstrapScript"];
  self.fs = [[[FileSystemHelper alloc] initWithJSContextRef:(JSContextRef)self.jscocoa.ctx] autorelease];
}

@end
