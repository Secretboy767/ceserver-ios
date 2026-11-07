# RuntimeHost

RuntimeHost is a sample iOS app that starts ESPRuntime from the app launch lifecycle.
On first launch, the runtime creates `Documents/Scripts`; valid `.js` files in that
folder run in the app's JavaScriptCore context on launch. Use **Run Scripts Now** to
rescan and run them without relaunching.

## Run on a device

1. Open `RuntimeHost.xcodeproj` in Xcode.
2. Select the `RuntimeHost` scheme and a connected iPhone.
3. In the target's **Signing & Capabilities** settings, select your Apple development
   team and set a bundle identifier that you control.
4. Build and run the app.
5. In Files, open **On My iPhone > RuntimeHost > Scripts** and add `.js` files.

The app enables Documents sharing so its `Scripts` folder appears in Files. The
simulator build can also be installed and launched in an iOS Simulator. Scripts are
executed only by this host app; loading the dylib into another process does not start
the runtime.
