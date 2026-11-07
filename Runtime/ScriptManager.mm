#import "ScriptManager.h"

#import "Logger.h"
#import "ScriptValidator.h"

@interface ScriptManager ()
@property (nonatomic, copy, readwrite) NSString *baseDirectory;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *scriptFiles;
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, id> *configuration;
@property (nonatomic, strong, readwrite) Logger *logger;
@end

@implementation ScriptManager

- (instancetype)initWithBaseDirectory:(NSString *)baseDirectory {
    self = [super init];
    if (self) {
        _baseDirectory = [baseDirectory copy] ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
        _scriptFiles = @[];
        _configuration = @{};
        _logger = [Logger sharedLogger];
    }
    return self;
}

- (BOOL)loadConfiguration:(NSError **)error {
    NSString *configPath = [self.baseDirectory stringByAppendingPathComponent:@"config.json"];
    NSData *configData = [NSData dataWithContentsOfFile:configPath];

    if (configData.length == 0) {
        self.configuration = @{
            @"allowedScripts": @[],
            @"requiredScripts": @[],
            @"maxFileSizeBytes": @1048576,
            @"metadata": @{}
        };
        return YES;
    }

    NSError *parseError = nil;
    id object = [NSJSONSerialization JSONObjectWithData:configData options:0 error:&parseError];
    if (parseError != nil) {
        if (error) {
            *error = parseError;
        }
        return NO;
    }

    if (![object isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"ESP.Runtime" code:200 userInfo:@{NSLocalizedDescriptionKey: @"Configuration file must contain a dictionary."}];
        }
        return NO;
    }

    self.configuration = (NSDictionary *)object;
    return YES;
}

- (BOOL)reloadScriptsWithError:(NSError **)error {
    NSError *directoryError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:self.baseDirectory
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:&directoryError]) {
        if (error) {
            *error = directoryError;
        }
        return NO;
    }

    NSError *localError = nil;
    if (![self loadConfiguration:&localError]) {
        if (error) {
            *error = localError;
        }
        return NO;
    }

    NSArray<NSString *> *discovered = [self discoverScriptsWithError:&localError];
    if (localError != nil) {
        if (error) {
            *error = localError;
        }
        return NO;
    }

    NSNumber *maxFileSize = self.configuration[@"maxFileSizeBytes"] ?: @1048576;
    NSMutableArray<NSString *> *validatedScripts = [NSMutableArray array];

    for (NSString *scriptName in discovered) {
        NSString *fullPath = [self.baseDirectory stringByAppendingPathComponent:scriptName];
        NSError *validationError = nil;
        if (![ScriptValidator validateScriptAtPath:fullPath
                                      baseDirectory:self.baseDirectory
                                       maxFileSize:[maxFileSize unsignedIntegerValue]
                                         allowlist:@[]
                                             error:&validationError]) {
            if (error) {
                *error = validationError;
            }
            return NO;
        }
        [validatedScripts addObject:scriptName];
    }

    self.scriptFiles = [validatedScripts sortedArrayUsingSelector:@selector(compare:)];
    return YES;
}

- (NSArray<NSString *> *)discoverScriptsWithError:(NSError **)error {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:self.baseDirectory isDirectory:&isDirectory] || !isDirectory) {
        if (error) {
            *error = [NSError errorWithDomain:@"ESP.Runtime" code:201 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Script directory does not exist: %@", self.baseDirectory]}];
        }
        return @[];
    }

    NSArray<NSString *> *directoryEntries = [fileManager contentsOfDirectoryAtPath:self.baseDirectory error:error];
    if (directoryEntries == nil) {
        return @[];
    }

    NSMutableArray<NSString *> *scriptNames = [NSMutableArray array];
    for (NSString *entry in directoryEntries) {
        if (![entry.pathExtension.lowercaseString isEqualToString:@"js"]) {
            continue;
        }

        NSString *fullPath = [self.baseDirectory stringByAppendingPathComponent:entry];
        BOOL isTargetDirectory = NO;
        if (![fileManager fileExistsAtPath:fullPath isDirectory:&isTargetDirectory] || isTargetDirectory) {
            continue;
        }

        NSError *validationError = nil;
        if (![ScriptValidator isAllowedScript:entry allowlist:@[] error:&validationError]) {
            if (error) {
                *error = validationError;
            }
            return @[];
        }
        [scriptNames addObject:entry];
    }

    return [scriptNames sortedArrayUsingSelector:@selector(compare:)];
}

- (NSString *)contentOfScriptAtPath:(NSString *)scriptPath error:(NSError **)error {
    if (scriptPath.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"ESP.Runtime" code:202 userInfo:@{NSLocalizedDescriptionKey: @"Script path cannot be empty."}];
        }
        return nil;
    }

    NSString *resolvedScript = [[[NSURL fileURLWithPath:scriptPath isDirectory:NO] URLByResolvingSymlinksInPath] path];
    NSString *resolvedBase = [[[NSURL fileURLWithPath:self.baseDirectory isDirectory:YES] URLByResolvingSymlinksInPath] path];
    if (![resolvedScript isEqualToString:resolvedBase] && ![resolvedScript hasPrefix:[resolvedBase stringByAppendingString:@"/"]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"ESP.Runtime" code:203 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Script path is outside the script directory: %@", scriptPath]}];
        }
        return nil;
    }

    NSError *readError = nil;
    NSString *content = [NSString stringWithContentsOfFile:resolvedScript encoding:NSUTF8StringEncoding error:&readError];
    if (!content) {
        if (error) {
            *error = readError ?: [NSError errorWithDomain:@"ESP.Runtime" code:204 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to read script: %@", scriptPath]}];
        }
        return nil;
    }

    return content;
}

- (NSDictionary<NSString *, id> *)scriptMetadataForFile:(NSString *)scriptName {
    if (scriptName.length == 0) {
        return @{};
    }

    NSString *fullPath = [self.baseDirectory stringByAppendingPathComponent:scriptName];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:fullPath error:nil] ?: @{};
    NSNumber *size = attributes[NSFileSize] ?: @0;
    NSDictionary *metadata = self.configuration[@"metadata"] ?: @{};
    NSArray *allowlist = self.configuration[@"allowedScripts"] ?: @[];

    return @{
        @"filename": scriptName,
        @"sizeBytes": size,
        @"sha256": [ScriptValidator sha256ForFileAtPath:fullPath error:nil] ?: @"",
        @"allowlisted": @([ScriptValidator isAllowedScript:scriptName allowlist:allowlist error:nil]),
        @"metadata": metadata
    };
}

@end
