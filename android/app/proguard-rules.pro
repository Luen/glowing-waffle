# R8 rules for release builds.

# shared_preferences_android 2.5.x drives its Pigeon API from Dart through JNI
# (package:jni) instead of a method channel, and package:jni looks classes and
# members up by their Java names: SharedPreferencesApiRegistrar, its suspend
# entry points, and the kotlin.coroutines/kotlin.Result types those signatures
# mention. R8 renames and strips anything it cannot see a Java reference to, so
# a minified build threw NoSuchMethodError/ClassNotFoundException on every
# preference read (issue #58).
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Keep the names that those lookups use. Shrinking and optimisation still run,
# so the APK stays small while any JNI-by-name lookup keeps working.
-dontobfuscate
