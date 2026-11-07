#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ScriptValidator : NSObject

+ (BOOL)isAllowedScript:(NSString *)scriptName allowlist:(NSArray<NSString *> *)allowlist error:(NSError **)error;

+ (BOOL)validateScriptAtPath:(NSString *)path
                baseDirectory:(NSString *)baseDirectory
                 maxFileSize:(NSUInteger)maxFileSize
                   allowlist:(NSArray<NSString *> *)allowlist
                       error:(NSError **)error;

+ (NSString *)sha256ForFileAtPath:(NSString *)path error:(NSError **)error;

+ (BOOL)isValidScriptFilename:(NSString *)filename;

@end

NS_ASSUME_NONNULL_END
