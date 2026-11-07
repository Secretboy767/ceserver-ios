#import "ESPRuntime.h"

#import "Logger.h"
#import "ScriptManager.h"
#import "ScriptValidator.h"

#import <JavaScriptCore/JavaScriptCore.h>
#import <UIKit/UIKit.h>

static NSString * const ESPRuntimeTerminalDidUpdateNotification = @"ESPRuntimeTerminalDidUpdateNotification";

@interface ESPRuntimeErrorTerminalViewController : UIViewController
@property (nonatomic, copy) NSArray<NSString *> *messages;
@end

@implementation ESPRuntimeErrorTerminalViewController {
    UITextView *_outputView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.04 green:0.05 blue:0.05 alpha:1.0];
    self.title = @"Error terminal";

    _outputView = [[UITextView alloc] init];
    _outputView.translatesAutoresizingMaskIntoConstraints = NO;
    _outputView.editable = NO;
    _outputView.selectable = YES;
    _outputView.backgroundColor = self.view.backgroundColor;
    _outputView.textColor = UIColor.greenColor;
    _outputView.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightRegular];
    _outputView.text = self.messages.count > 0
        ? [self.messages componentsJoinedByString:@"\n\n"]
        : @"No errors logged.";

    UIButton *copyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    copyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [copyButton setTitle:@"Copy log" forState:UIControlStateNormal];
    [copyButton addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];

    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    [closeButton setTitle:@"Close" forState:UIControlStateNormal];
    [closeButton addTarget:self action:@selector(closeTerminal) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[copyButton, closeButton]];
    actions.translatesAutoresizingMaskIntoConstraints = NO;
    actions.axis = UILayoutConstraintAxisHorizontal;
    actions.distribution = UIStackViewDistributionEqualSpacing;

    [self.view addSubview:_outputView];
    [self.view addSubview:actions];
    [NSLayoutConstraint activateConstraints:@[
        [actions.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16.0],
        [actions.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16.0],
        [actions.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8.0],
        [_outputView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:8.0],
        [_outputView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-8.0],
        [_outputView.topAnchor constraintEqualToAnchor:actions.bottomAnchor constant:8.0],
        [_outputView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-8.0]
    ]];

    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(refreshOutput)
                                               name:ESPRuntimeTerminalDidUpdateNotification
                                             object:nil];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)refreshOutput {
    self.messages = [ESPRuntime sharedRuntime].terminalErrorMessages;
    _outputView.text = self.messages.count > 0
        ? [self.messages componentsJoinedByString:@"\n\n"]
        : @"No errors logged.";
}

- (void)copyLog {
    UIPasteboard.generalPasteboard.string = _outputView.text ?: @"";
}

- (void)closeTerminal {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

@interface ESPRuntime ()
@property (nonatomic, strong, readwrite) ScriptManager *scriptManager;
@property (nonatomic, strong, readwrite) JSContext *javascriptContext;
@property (nonatomic, copy, readwrite) NSString *documentsDirectory;
@property (nonatomic, assign, readwrite) BOOL isRunning;
@property (nonatomic, strong) UIButton *runScriptsButton;
@property (nonatomic, strong) UIButton *openTerminalButton;
@property (nonatomic, copy) void (^runScriptsCompletion)(NSError * _Nullable error);
@property (nonatomic, assign) BOOL observingWindowAvailability;
@property (nonatomic, strong) NSMutableArray<NSString *> *mutableTerminalErrorMessages;
- (BOOL)prepareRuntimeWithError:(NSError **)error;
- (void)installCreateButton;
- (void)runtimeWindowDidBecomeAvailable:(NSNotification *)notification;
- (UIWindow *)activeKeyWindow;
- (void)runDocumentsScripts:(UIButton *)sender;
- (void)presentRunSummaryFromButton:(UIButton *)sender error:(NSError *)error;
- (void)recordTerminalError:(NSString *)message;
@end

@implementation ESPRuntime

+ (void)load {
    if (self == [ESPRuntime class]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            ESPRuntime *runtime = [self sharedRuntime];
            [runtime installCreateButton];
        });
    }
}

+ (instancetype)sharedRuntime {
    static ESPRuntime *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        sharedInstance = [[self alloc] initWithApplicationRoot:documentsDirectory];
    });
    return sharedInstance;
}

- (instancetype)initWithApplicationRoot:(NSString *)applicationRoot {
    self = [super init];
    if (self) {
        _documentsDirectory = [applicationRoot copy] ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
        _scriptManager = [[ScriptManager alloc] initWithBaseDirectory:_documentsDirectory];
        _isRunning = NO;
        _mutableTerminalErrorMessages = [NSMutableArray array];
    }
    return self;
}

- (BOOL)startWithError:(NSError **)error {
    if (self.isRunning) {
        return YES;
    }

    if (![self prepareRuntimeWithError:error]) {
        return NO;
    }

    return [self executeScripts:@[] error:error];
}

- (BOOL)prepareRuntimeWithError:(NSError **)error {
    if (self.isRunning) {
        return YES;
    }

    NSError *localError = nil;
    if (![self.scriptManager reloadScriptsWithError:&localError]) {
        [self recordTerminalError:[NSString stringWithFormat:@"Unable to read Documents at %@: %@",
                                   self.documentsDirectory,
                                   localError.localizedDescription ?: @"Unknown error"]];
        if (error) {
            *error = localError;
        }
        return NO;
    }

    self.javascriptContext = [[JSContext alloc] init];
    __weak ESPRuntime *weakSelf = self;
    self.javascriptContext.exceptionHandler = ^(JSContext *context, JSValue *exception) {
        NSString *message = exception ? exception.toString : @"Unknown JavaScript exception";
        [weakSelf recordTerminalError:[NSString stringWithFormat:@"JavaScript exception: %@", message]];
        [[Logger sharedLogger] logScriptEventWithFilename:@"javascript_exception"
                                                timestamp:[NSDate date]
                                                duration:0.0
                                                 success:NO
                                                message:@"JavaScript exception"
                                          exceptionInfo:message
                                             integrity:@"unchecked"
                                         sourceContext:@"JSContext.exceptionHandler"];
    };

    self.isRunning = YES;
    return YES;
}

- (BOOL)reloadWithError:(NSError **)error {
    self.isRunning = NO;
    self.javascriptContext = nil;
    if (![self prepareRuntimeWithError:error]) {
        return NO;
    }

    return [self executeScripts:@[] error:error];
}

- (BOOL)executeScripts:(NSArray<NSString *> *)scripts error:(NSError **)error {
    if (![self prepareRuntimeWithError:error]) {
        return NO;
    }

    NSArray<NSString *> *scriptsToExecute = scripts.count > 0 ? scripts : self.scriptManager.scriptFiles;
    if (scriptsToExecute.count == 0) {
        return YES;
    }

    for (NSString *scriptName in scriptsToExecute) {
        if (![self.scriptManager.scriptFiles containsObject:scriptName]) {
            NSError *scriptError = [NSError errorWithDomain:@"ESP.Runtime" code:301 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Script was not discovered in the Documents directory: %@", scriptName]}];
            [self recordTerminalError:scriptError.localizedDescription];
            if (error) {
                *error = scriptError;
            }
            return NO;
        }

        NSString *fullPath = [self.scriptManager.baseDirectory stringByAppendingPathComponent:scriptName];
        NSNumber *maxFileSize = self.scriptManager.configuration[@"maxFileSizeBytes"] ?: @1048576;
        NSError *validationError = nil;
        if (![ScriptValidator validateScriptAtPath:fullPath
                                      baseDirectory:self.scriptManager.baseDirectory
                                       maxFileSize:maxFileSize.unsignedIntegerValue
                                         allowlist:@[]
                                             error:&validationError]) {
            [self recordTerminalError:[NSString stringWithFormat:@"Script validation failed for %@: %@",
                                       scriptName,
                                       validationError.localizedDescription ?: @"Unknown error"]];
            if (error) {
                *error = validationError;
            }
            return NO;
        }

        NSError *readError = nil;
        NSString *scriptSource = [self.scriptManager contentOfScriptAtPath:fullPath error:&readError];
        if (scriptSource == nil) {
            [self recordTerminalError:[NSString stringWithFormat:@"Unable to read %@: %@",
                                       scriptName,
                                       readError.localizedDescription ?: @"Unknown error"]];
            if (error) {
                *error = readError;
            }
            return NO;
        }

        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        JSValue *result = [self.javascriptContext evaluateScript:scriptSource];
        CFAbsoluteTime duration = CFAbsoluteTimeGetCurrent() - start;

        BOOL success = YES;
        NSString *exceptionInfo = @"";
        if (self.javascriptContext.exception) {
            success = NO;
            exceptionInfo = self.javascriptContext.exception.toString;
        }

        NSString *integrity = [ScriptValidator sha256ForFileAtPath:fullPath error:nil] ?: @"unverified";
        [[Logger sharedLogger] logScriptEventWithFilename:scriptName
                                                timestamp:[NSDate date]
                                                duration:duration
                                                 success:success
                                                message:success ? @"Script executed successfully" : @"Script execution failed"
                                          exceptionInfo:exceptionInfo
                                             integrity:integrity
                                         sourceContext:@"ESPRuntime executeScripts"];

        if (!success) {
            NSString *failureMessage = [NSString stringWithFormat:@"JavaScript execution failed for %@: %@",
                                        scriptName,
                                        exceptionInfo];
            [self recordTerminalError:failureMessage];
            if (error) {
                *error = [NSError errorWithDomain:@"ESP.Runtime" code:300 userInfo:@{NSLocalizedDescriptionKey: failureMessage}];
            }
            return NO;
        }

        if (result != nil && ![result isUndefined] && ![result isNull]) {
            NSString *resultDescription = [result toString];
            if (resultDescription.length > 0) {
                [[Logger sharedLogger] logScriptEventWithFilename:[NSString stringWithFormat:@"%@_result", scriptName]
                                                        timestamp:[NSDate date]
                                                        duration:0.0
                                                         success:YES
                                                        message:resultDescription
                                                  exceptionInfo:@""
                                                     integrity:@"n/a"
                                                 sourceContext:@"ESPRuntime evaluateScript"];
            }
        }
    }

    return YES;
}

- (NSArray<NSDictionary *> *)lastExecutionLogs {
    return [[Logger sharedLogger] entries];
}

- (NSArray<NSString *> *)terminalErrorMessages {
    @synchronized (self.mutableTerminalErrorMessages) {
        return [self.mutableTerminalErrorMessages copy];
    }
}

- (void)recordTerminalError:(NSString *)message {
    if (message.length == 0) {
        return;
    }

    NSString *entry = [NSString stringWithFormat:@"[%@] %@",
                       [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                      dateStyle:NSDateFormatterMediumStyle
                                                      timeStyle:NSDateFormatterMediumStyle],
                       message];
    @synchronized (self.mutableTerminalErrorMessages) {
        [self.mutableTerminalErrorMessages addObject:entry];
        if (self.mutableTerminalErrorMessages.count > 200) {
            [self.mutableTerminalErrorMessages removeObjectsInRange:NSMakeRange(0, self.mutableTerminalErrorMessages.count - 200)];
        }
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:ESPRuntimeTerminalDidUpdateNotification object:self];
    });
}

- (void)installCreateButton {
    __weak ESPRuntime *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        ESPRuntime *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        UIWindow *window = [strongSelf activeKeyWindow];
        if (window.rootViewController != nil) {
            [strongSelf showRunScriptsButtonInView:window.rootViewController.view completion:nil];
            if (strongSelf.observingWindowAvailability) {
                [NSNotificationCenter.defaultCenter removeObserver:strongSelf
                                                              name:UIApplicationDidBecomeActiveNotification
                                                            object:nil];
                [NSNotificationCenter.defaultCenter removeObserver:strongSelf
                                                              name:UIWindowDidBecomeKeyNotification
                                                            object:nil];
                strongSelf.observingWindowAvailability = NO;
            }
            return;
        }

        if (!strongSelf.observingWindowAvailability) {
            [NSNotificationCenter.defaultCenter addObserver:strongSelf
                                                   selector:@selector(runtimeWindowDidBecomeAvailable:)
                                                       name:UIApplicationDidBecomeActiveNotification
                                                     object:nil];
            [NSNotificationCenter.defaultCenter addObserver:strongSelf
                                                   selector:@selector(runtimeWindowDidBecomeAvailable:)
                                                       name:UIWindowDidBecomeKeyNotification
                                                     object:nil];
            strongSelf.observingWindowAvailability = YES;
        }
    });
}

- (void)runtimeWindowDidBecomeAvailable:(__unused NSNotification *)notification {
    [self installCreateButton];
}

- (UIWindow *)activeKeyWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]] ||
            scene.activationState != UISceneActivationStateForegroundActive) {
            continue;
        }

        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) {
                return window;
            }
        }
    }

    return UIApplication.sharedApplication.keyWindow;
}

- (void)showRunScriptsButtonInViewController:(UIViewController *)viewController
                                  completion:(void (^)(NSError * _Nullable error))completion {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showRunScriptsButtonInViewController:viewController completion:completion];
        });
        return;
    }

    [self showRunScriptsButtonInView:viewController.view completion:completion];
}

- (void)showRunScriptsButtonInView:(UIView *)view
                        completion:(void (^)(NSError * _Nullable error))completion {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showRunScriptsButtonInView:view completion:completion];
        });
        return;
    }

    [self.runScriptsButton removeFromSuperview];
    self.runScriptsCompletion = [completion copy];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:@"Run" forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.backgroundColor = UIColor.systemBlueColor;
    button.layer.cornerRadius = 8.0;
    [button addTarget:self
               action:@selector(runDocumentsScripts:)
     forControlEvents:UIControlEventTouchUpInside];

    [view addSubview:button];
    UIButton *terminalButton = [UIButton buttonWithType:UIButtonTypeSystem];
    terminalButton.translatesAutoresizingMaskIntoConstraints = NO;
    [terminalButton setTitle:@"Errors" forState:UIControlStateNormal];
    [terminalButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    terminalButton.backgroundColor = [UIColor colorWithRed:0.25 green:0.20 blue:0.20 alpha:1.0];
    terminalButton.layer.cornerRadius = 8.0;
    [terminalButton addTarget:self action:@selector(openErrorTerminal) forControlEvents:UIControlEventTouchUpInside];
    [view addSubview:terminalButton];
    [NSLayoutConstraint activateConstraints:@[
        [button.topAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.topAnchor constant:12.0],
        [button.trailingAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.trailingAnchor constant:-12.0],
        [button.widthAnchor constraintEqualToConstant:72.0],
        [button.heightAnchor constraintEqualToConstant:36.0],
        [terminalButton.topAnchor constraintEqualToAnchor:button.topAnchor],
        [terminalButton.trailingAnchor constraintEqualToAnchor:button.leadingAnchor constant:-8.0],
        [terminalButton.widthAnchor constraintEqualToConstant:72.0],
        [terminalButton.heightAnchor constraintEqualToAnchor:button.heightAnchor]
    ]];
    self.runScriptsButton = button;
    self.openTerminalButton = terminalButton;
}

- (void)runDocumentsScripts:(UIButton *)sender {
    sender.enabled = NO;

    NSError *error = nil;
    BOOL succeeded = [self reloadWithError:&error];
    if (!succeeded) {
        NSLog(@"Unable to execute JavaScript files in %@: %@",
              self.documentsDirectory,
              error.localizedDescription ?: @"Unknown error");
        [sender setTitle:@"Failed" forState:UIControlStateNormal];
    } else if (self.scriptManager.scriptFiles.count == 0) {
        [sender setTitle:@"No .js" forState:UIControlStateNormal];
    } else {
        [sender setTitle:[NSString stringWithFormat:@"Ran %lu", (unsigned long)self.scriptManager.scriptFiles.count]
                forState:UIControlStateNormal];
    }

    [self presentRunSummaryFromButton:sender error:error];

    void (^completion)(NSError *) = self.runScriptsCompletion;
    self.runScriptsCompletion = nil;
    if (completion) {
        completion(succeeded ? nil : error);
    }

    __weak ESPRuntime *weakSelf = self;
    __weak UIButton *weakButton = sender;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIButton *button = weakButton;
        [button removeFromSuperview];
        if (weakSelf.runScriptsButton == button) {
            weakSelf.runScriptsButton = nil;
        }
    });
}

- (void)presentRunSummaryFromButton:(UIButton *)sender error:(NSError *)error {
    UIViewController *viewController = sender.window.rootViewController;
    while (viewController.presentedViewController != nil) {
        viewController = viewController.presentedViewController;
    }

    if (viewController == nil) {
        return;
    }

    NSString *message = nil;
    if (error != nil) {
        message = [NSString stringWithFormat:@"Documents: %@\n\n%@", self.documentsDirectory, error.localizedDescription];
    } else if (self.scriptManager.scriptFiles.count == 0) {
        message = [NSString stringWithFormat:@"No .js files found directly in:\n%@", self.documentsDirectory];
    } else {
        message = [NSString stringWithFormat:@"Executed %lu JavaScript file(s) in:\n%@\n\n%@",
                   (unsigned long)self.scriptManager.scriptFiles.count,
                   self.documentsDirectory,
                   [self.scriptManager.scriptFiles componentsJoinedByString:@"\n"]];
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Documents scripts"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [viewController presentViewController:alert animated:YES completion:nil];
}

- (void)openErrorTerminal {
    UIWindow *window = [self activeKeyWindow];
    UIViewController *presenter = window.rootViewController;
    while (presenter.presentedViewController != nil) {
        presenter = presenter.presentedViewController;
    }
    if (presenter == nil) {
        [self recordTerminalError:@"Unable to open the error terminal: no active view controller."];
        return;
    }

    ESPRuntimeErrorTerminalViewController *terminal = [[ESPRuntimeErrorTerminalViewController alloc] init];
    terminal.messages = self.terminalErrorMessages;
    terminal.modalPresentationStyle = UIModalPresentationFullScreen;
    [presenter presentViewController:terminal animated:YES completion:nil];
}

@end
