#import "ESPRuntime.h"

#import "Logger.h"
#import "ScriptManager.h"
#import "ScriptValidator.h"

#import <JavaScriptCore/JavaScriptCore.h>

@interface ESPRuntime ()
@property (nonatomic, strong, readwrite) ScriptManager *scriptManager;
@property (nonatomic, strong, readwrite) JSContext *javascriptContext;
@property (nonatomic, copy, readwrite) NSString *documentsDirectory;
@property (nonatomic, assign, readwrite) BOOL isRunning;
- (BOOL)prepareRuntimeWithError:(NSError **)error;
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

@end
