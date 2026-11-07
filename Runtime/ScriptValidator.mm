#import "ScriptValidator.h"

#import <CommonCrypto/CommonCrypto.h>
#import <Foundation/Foundation.h>

@implementation ScriptValidator

+ (BOOL)isAllowedScript:(NSString *)scriptName allowlist:(NSArray<NSString *> *)allowlist error:(NSError **)error {
    if (scriptName.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"ESP.Runtime" code:100 userInfo:@{NSLocalizedDescriptionKey: @"Script name cannot be empty."}];
        }
        return NO;
    }

    NSString *normalizedName = scriptName.lastPathComponent;
    if (![self isValidScriptFilename:normalizedName]) {
        if (error) {
            *error = [NSError errorWithDomain:@"ESP.Runtime" code:101 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Invalid script filename: %@", scriptName]}];
        }
        return NO;
    }

    if (![scriptName isEqualToString:normalizedName]) {
        if (error) {
            *error = [NSError errorWithDomain:@"ESP.Runtime" code:102 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unsafe script path detected: %@", scriptName]}];
        }
        return NO;
    }

    if (allowlist.count > 0 && ![allowlist containsObject:normalizedName]) {
        if (error) {
            *error = [NSError errorWithDomain:@"ESP.Runtime" code:103 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Script is not in the allowlist: %@", normalizedName]}];
        }
        return NO;
    }

    return YES;
}

+ (BOOL)validateScriptAtPath:(NSString *)path
                baseDirectory:(NSString *)baseDirectory
                 maxFileSize:(NSUInteger)maxFileSize
                   allowlist:(NSArray<NSString *> *)allowlist
                       error:(NSError **)error {
    if (path.length == 0 || baseDirectory.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"ESP.Runtime" code:104 userInfo:@{NSLocalizedDescriptionKey: @"Missing script path or base directory."}];
        }
        return NO;
    }

    NSString *resolvedBase = [[[NSURL fileURLWithPath:baseDirectory isDirectory:YES] URLByResolvingSymlinksInPath] path];
    NSString *resolvedPath = [[[NSURL fileURLWithPath:path isDirectory:NO] URLByResolvingSymlinksInPath] path];

    if (![resolvedPath isEqualToString:resolvedBase] && ![resolvedPath hasPrefix:[resolvedBase stringByAppendingString:@"/"]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"ESP.Runtime" code:105 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Script is outside the configured base directory: %@", path]}];
        }
        return NO;
    }

    BOOL isDirectory = NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:resolvedPath isDirectory:&isDirectory];
    if (!exists || isDirectory) {
        if (error) {
            *error = [NSError errorWithDomain:@"ESP.Runtime" code:106 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Script file does not exist or is a directory: %@", path]}];
        }
        return NO;
    }

    NSDictionary<NSFileAttributeKey, id> *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:resolvedPath error:nil];
    NSNumber *fileSize = attributes[NSFileSize];
    if (fileSize == nil || [fileSize unsignedIntegerValue] == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"ESP.Runtime" code:107 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Script is empty or unreadable: %@", path]}];
        }
        return NO;
    }

    if ([fileSize unsignedIntegerValue] > maxFileSize) {
        if (error) {
            *error = [NSError errorWithDomain:@"ESP.Runtime" code:108 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Script exceeds size limit: %@ (%@ bytes)", path, fileSize]}];
        }
        return NO;
    }

    NSString *scriptName = [resolvedPath lastPathComponent];
    if (![self isAllowedScript:scriptName allowlist:allowlist error:error]) {
        return NO;
    }

    return YES;
}

+ (NSString *)sha256ForFileAtPath:(NSString *)path error:(NSError **)error {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (handle == nil) {
        if (error) {
            *error = [NSError errorWithDomain:@"ESP.Runtime" code:109 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to open script for integrity check: %@", path]}];
        }
        return nil;
    }

    CC_SHA256_CTX hashContext;
    CC_SHA256_Init(&hashContext);

    BOOL isDone = NO;
    while (!isDone) {
        NSData *data = [handle readDataOfLength:4096];
        if (data.length == 0) {
            isDone = YES;
            continue;
        }
        CC_SHA256_Update(&hashContext, data.bytes, (CC_LONG)data.length);
    }

    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &hashContext);

    NSMutableString *hexHash = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (size_t index = 0; index < CC_SHA256_DIGEST_LENGTH; index++) {
        [hexHash appendFormat:@"%02x", digest[index]];
    }

    return [hexHash copy];
}

+ (BOOL)isValidScriptFilename:(NSString *)filename {
    if (filename.length == 0) {
        return NO;
    }

    NSString *baseName = filename.lastPathComponent;
    if ([baseName isEqualToString:@"."] || [baseName isEqualToString:@".."]) {
        return NO;
    }

    if (![baseName hasSuffix:@".js"]) {
        return NO;
    }

    NSCharacterSet *invalidCharacterSet = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"] invertedSet];
    return [baseName rangeOfCharacterFromSet:invalidCharacterSet].location == NSNotFound;
}

@end
