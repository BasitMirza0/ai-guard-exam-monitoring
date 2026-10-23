Vendored from the installed pub.dev google_mlkit_image_labeling 0.12.0, with its original license.
Dart, Android and Objective-C implementation files are unchanged.

The iOS podspec now uses GoogleMLKit 7.0.x and iOS 15.5. The original combination
had two conflicts: GoogleMLKit 5.x vs 6.x root pods, and MLKitCommon 11.x's
GoogleUtilities <8 vs Firebase 11.x / GoogleSignIn 8.x's GoogleUtilities 8.x.
ML Kit 7 uses MLKitCommon 12, which supports GoogleUtilities 8.
Native version 7 and the deployment target match upstream plugin podspecs.

Only native iOS requirements and the development-only sibling pubspec override
were changed. The latter was removed to resolve commons from the app lockfile.
Keep this directory in source control. Do not modify the global pub cache.
CocoaPods resolution and native compilation still need validation with Xcode
and CocoaPods installed. See ../../docs/IOS_IPHONE_SETUP.md for the audit.
