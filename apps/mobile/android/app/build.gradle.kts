plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "cn.semesteros.semester_os"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "cn.semesteros.semester_os"
        // Opt-in isolated sandbox for device verification; normal builds keep
        // their existing application ID, data and launcher name.
        val qa = providers.gradleProperty("semesterosQa").orNull == "true"
        if (qa) applicationIdSuffix = ".qa"
        resValue("string", "app_label", if (qa) "拾日 · 验证" else "拾日")
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // scripts/build_release.py signs the aligned APK with the existing
            // upgrade-compatible key; private signing material stays outside Git.
        }
    }
}

dependencies {
    implementation("androidx.webkit:webkit:1.15.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
