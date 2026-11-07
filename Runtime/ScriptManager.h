#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class Logger;

@interface ScriptManager : NSObject

@property (nonatomic, copy, readonly) NSString *baseDirectory;
@property (nonatomic, copy, readonly) NSArray<NSString *> *scriptFiles;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *configuration;
@property (nonatomic, strong, readonly) Logger *logger;

- (instancetype)initWithBaseDirectory:(NSString *)baseDirectory NS_DESIGNATED_INITIALIZER;
- (BOOL)loadConfiguration:(NSError **)error;
- (BOOL)reloadScriptsWithError:(NSError **)error;
- (NSArray<NSString *> *)discoverScriptsWithError:(NSError **)error;
- (NSString *)contentOfScriptAtPath:(NSString *)scriptPath error:(NSError **)error;
- (NSDictionary<NSString *, id> *)scriptMetadataForFile:(NSString *)scriptName;

@end

NS_ASSUME_NONNULL_END
