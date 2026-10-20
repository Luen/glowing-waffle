import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (#11).
//
// The upload key comes from android/key.properties (git-ignored) or from the
// same names as environment variables, so CI can sign from secrets without a
// keystore in the repository:
//
//   storeFile=../upload.jks        ANDROID_KEYSTORE_PATH
//   storePassword=…                ANDROID_KEYSTORE_PASSWORD
//   keyAlias=upload                ANDROID_KEY_ALIAS
//   keyPassword=…                  ANDROID_KEY_PASSWORD
//
// Relative storeFile paths are resolved against android/app, like the Flutter
// template does. Without a key the release build stays debug-signed (fine for
// `flutter run --release`, not shippable).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun signingValue(property: String, environment: String): String? =
    keystoreProperties.getProperty(property) ?: System.getenv(environment)

val uploadStoreFile = signingValue("storeFile", "ANDROID_KEYSTORE_PATH")
val uploadStorePassword = signingValue("storePassword", "ANDROID_KEYSTORE_PASSWORD")
val uploadKeyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
val uploadKeyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")
val hasUploadKey = !uploadStoreFile.isNullOrBlank() &&
    !uploadStorePassword.isNullOrBlank() &&
    !uploadKeyAlias.isNullOrBlank() &&
    !uploadKeyPassword.isNullOrBlank()
if (!hasUploadKey) {
    logger.lifecycle(
        "Release builds are debug-signed. Set android/key.properties (or " +
            "ANDROID_KEYSTORE_PATH, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS, " +
            "ANDROID_KEY_PASSWORD) to sign with the upload key."
    )
}

android {
    namespace = "dev.luen.glowingwaffle"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.luen.glowingwaffle"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadKey) {
            create("release") {
                storeFile = file(uploadStoreFile!!)
                storePassword = uploadStorePassword
                keyAlias = uploadKeyAlias
                keyPassword = uploadKeyPassword
            }
        }
    }

    packaging {
        jniLibs {
            // Only 64-bit ARM (issue #40). Flutter passes its own target
            // platforms to Gradle and overrides ndk.abiFilters, and plugin
            // AARs (sherpa-onnx) ship every ABI, so the unused ones are
            // dropped here instead. That also keeps Play from offering the
            // APK to devices whose engine is not in it.
            excludes += listOf(
                "lib/armeabi-v7a/**",
                "lib/x86/**",
                "lib/x86_64/**",
            )
        }
    }

    buildTypes {
        release {
            // Debug keys keep `flutter run --release` working for contributors;
            // see the upload-key block above for real releases.
            signingConfig = if (hasUploadKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
