#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Logger : NSObject

@property (nonatomic, copy, readonly) NSArray<NSDictionary *> *entries;

+ (instancetype)sharedLogger;

- (void)logScriptEventWithFilename:(NSString *)filename
                           timestamp:(NSDate *)timestamp
                           duration:(NSTimeInterval)duration
                            success:(BOOL)success
                           message:(NSString *)message
                     exceptionInfo:(NSString *)exceptionInfo
                        integrity:(NSString *)integrity
                    sourceContext:(NSString *)sourceContext;

@end

NS_ASSUME_NONNULL_END
