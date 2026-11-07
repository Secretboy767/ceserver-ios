#import <Foundation/Foundation.h>
#import <JavaScriptCore/JavaScriptCore.h>

NS_ASSUME_NONNULL_BEGIN

@class ScriptManager;
@class UIView;
@class UIViewController;

@interface ESPRuntime : NSObject

@property (nonatomic, strong, readonly) ScriptManager *scriptManager;
@property (nonatomic, strong, readonly) JSContext *javascriptContext;
@property (nonatomic, copy, readonly) NSString *documentsDirectory;
@property (nonatomic, assign, readonly) BOOL isRunning;

+ (instancetype)sharedRuntime;
- (instancetype)initWithApplicationRoot:(NSString *)applicationRoot NS_DESIGNATED_INITIALIZER;
// Executes top-level .js files in the application's Documents directory.
- (BOOL)startWithError:(NSError **)error;
- (BOOL)reloadWithError:(NSError **)error;
- (BOOL)executeScripts:(NSArray<NSString *> *)scripts error:(NSError **)error;
- (void)showRunScriptsButtonInViewController:(UIViewController *)viewController
                                  completion:(void (^)(NSError * _Nullable error))completion;
- (void)showRunScriptsButtonInView:(UIView *)view
                        completion:(void (^)(NSError * _Nullable error))completion;
- (NSArray<NSDictionary *> *)lastExecutionLogs;

@end

NS_ASSUME_NONNULL_END
