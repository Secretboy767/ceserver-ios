#import "Logger.h"

@interface Logger ()
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *mutableEntries;
@end

@implementation Logger

+ (instancetype)sharedLogger {
    static Logger *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableEntries = [NSMutableArray array];
    }
    return self;
}

- (NSArray<NSDictionary *> *)entries {
    return [self.mutableEntries copy];
}

- (void)logScriptEventWithFilename:(NSString *)filename
                           timestamp:(NSDate *)timestamp
                           duration:(NSTimeInterval)duration
                            success:(BOOL)success
                           message:(NSString *)message
                     exceptionInfo:(NSString *)exceptionInfo
                        integrity:(NSString *)integrity
                    sourceContext:(NSString *)sourceContext {
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    entry[@"filename"] = filename ?: @"unknown";
    entry[@"timestamp"] = timestamp ?: [NSDate date];
    entry[@"duration"] = @(duration);
    entry[@"success"] = @(success);
    entry[@"message"] = message ?: @"";
    entry[@"exceptionInfo"] = exceptionInfo ?: @"";
    entry[@"integrity"] = integrity ?: @"";
    entry[@"sourceContext"] = sourceContext ?: @"";

    [self.mutableEntries addObject:entry];
}

@end
