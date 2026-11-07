#import "ESPRuntime.h"

#import "Logger.h"
#import "ScriptManager.h"
#import "ScriptValidator.h"

#import <JavaScriptCore/JavaScriptCore.h>
#import <UIKit/UIKit.h>

@interface ESPRuntime ()
@property (nonatomic, strong, readwrite) ScriptManager *scriptManager;
@property (nonatomic, strong, readwrite) JSContext *javascriptContext;
@property (nonatomic, copy, readwrite) NSString *documentsDirectory;
@property (nonatomic, assign, readwrite) BOOL isRunning;
@property (nonatomic, strong) UIButton *createFolderButton;
@property (nonatomic, copy) void (^createFolderCompletion)(NSError * _Nullable error);
- (BOOL)prepareRuntimeWithError:(NSError **)error;
- (void)createScriptsDirectory:(UIButton *)sender;
@end

@implementation ESPRuntime

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
        NSString *scriptsDirectory = [_documentsDirectory stringByAppendingPathComponent:@"Scripts"];
        _scriptManager = [[ScriptManager alloc] initWithBaseDirectory:scriptsDirectory];
        _isRunning = NO;
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
        if (error) {
            *error = localError;
        }
        return NO;
    }

    self.javascriptContext = [[JSContext alloc] init];
    self.javascriptContext.exceptionHandler = ^(JSContext *context, JSValue *exception) {
        NSString *message = exception ? exception.toString : @"Unknown JavaScript exception";
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
            if (error) {
                *error = [NSError errorWithDomain:@"ESP.Runtime" code:301 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Script was not discovered in the Scripts directory: %@", scriptName]}];
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
            if (error) {
                *error = validationError;
            }
            return NO;
        }

        NSError *readError = nil;
        NSString *scriptSource = [self.scriptManager contentOfScriptAtPath:fullPath error:&readError];
        if (scriptSource == nil) {
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
            if (error) {
                *error = [NSError errorWithDomain:@"ESP.Runtime" code:300 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"JavaScript exception while executing %@: %@", scriptName, exceptionInfo]}];
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

- (void)showCreateButtonInView:(UIView *)view
                    completion:(void (^)(NSError * _Nullable error))completion {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showCreateButtonInView:view completion:completion];
        });
        return;
    }

    [self.createFolderButton removeFromSuperview];
    self.createFolderCompletion = [completion copy];

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:@"create" forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    button.backgroundColor = UIColor.systemBlueColor;
    button.layer.cornerRadius = 8.0;
    [button addTarget:self
               action:@selector(createScriptsDirectory:)
     forControlEvents:UIControlEventTouchUpInside];

    [view addSubview:button];
    [NSLayoutConstraint activateConstraints:@[
        [button.topAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.topAnchor constant:12.0],
        [button.trailingAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.trailingAnchor constant:-12.0],
        [button.widthAnchor constraintEqualToConstant:72.0],
        [button.heightAnchor constraintEqualToConstant:36.0]
    ]];
    self.createFolderButton = button;
}

- (void)createScriptsDirectory:(UIButton *)sender {
    sender.enabled = NO;

    NSError *error = nil;
    BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:self.scriptManager.baseDirectory
                                            withIntermediateDirectories:YES
                                                             attributes:nil
                                                                  error:&error];
    if (!created) {
        NSLog(@"Unable to create scripts directory at %@: %@",
              self.scriptManager.baseDirectory,
              error.localizedDescription ?: @"Unknown error");
    }

    void (^completion)(NSError *) = self.createFolderCompletion;
    self.createFolderCompletion = nil;
    if (completion) {
        completion(created ? nil : error);
    }

    __weak typeof(self) weakSelf = self;
    __weak UIButton *weakButton = sender;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIButton *button = weakButton;
        [button removeFromSuperview];
        if (weakSelf.createFolderButton == button) {
            weakSelf.createFolderButton = nil;
        }
    });
}

@end
