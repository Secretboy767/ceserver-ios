#import "AppDelegate.h"

#import "ESPRuntime.h"

@interface ScriptsViewController : UIViewController
@end

@implementation ScriptsViewController {
    UILabel *_statusLabel;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = @"JavaScript Runtime";
    titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleLargeTitle];
    titleLabel.textAlignment = NSTextAlignmentCenter;

    _statusLabel = [[UILabel alloc] init];
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _statusLabel.numberOfLines = 0;
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.text = @"Starting runtime…";

    UIButton *runButton = [UIButton buttonWithType:UIButtonTypeSystem];
    runButton.translatesAutoresizingMaskIntoConstraints = NO;
    [runButton setTitle:@"Run Scripts Now" forState:UIControlStateNormal];
    [runButton addTarget:self action:@selector(runScriptsNow) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[titleLabel, _statusLabel, runButton]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 20;
    stack.alignment = UIStackViewAlignmentFill;

    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-24],
        [stack.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
    ]];

    NSError *error = nil;
    if ([[ESPRuntime sharedRuntime] startWithError:&error]) {
        _statusLabel.text = @"Ready. Add .js files in Files > On My iPhone > RuntimeHost > Scripts. Scripts run when the app opens.";
    } else {
        _statusLabel.text = [NSString stringWithFormat:@"Runtime failed to start: %@", error.localizedDescription ?: @"Unknown error"];
        NSLog(@"ESPRuntime startup failed: %@", error);
    }
}

- (void)runScriptsNow {
    NSError *error = nil;
    if ([[ESPRuntime sharedRuntime] reloadWithError:&error]) {
        _statusLabel.text = @"Scripts folder refreshed and scripts executed.";
    } else {
        _statusLabel.text = [NSString stringWithFormat:@"Script run failed: %@", error.localizedDescription ?: @"Unknown error"];
        NSLog(@"ESPRuntime reload failed: %@", error);
    }
}

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[ScriptsViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

@end
