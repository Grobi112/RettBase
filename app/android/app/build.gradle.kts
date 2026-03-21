import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release-Signierung: android/key.properties + Keystore (nicht ins Repo committen)
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.mikefullbeck.rettbase"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.mikefullbeck.rettbase"
        // Eigenes Application: Notification-Kanäle vor MainActivity/FCM (Kaltstart)
        manifestPlaceholders["applicationName"] = "com.mikefullbeck.rettbase.RettBaseApplication"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias") ?: ""
                keyPassword = keystoreProperties.getProperty("keyPassword") ?: ""
                storePassword = keystoreProperties.getProperty("storePassword") ?: ""
                storeFile = keystoreProperties.getProperty("storeFile")?.let { rootProject.file(it) }
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // Nur für lokale Tests ohne key.properties – Play Store lehnt Debug-Signatur ab
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("androidx.appcompat:appcompat:1.6.1")
}

flutter {
    source = "../.."
}

// Alarm-Töne aus voices/ vor Build nach res/raw kopieren (automatische Übernahme bei Änderung)
val syncAlarmSounds = tasks.register<Exec>("syncAlarmSounds") {
    val script = project.file("../../scripts/setup_android_sounds.sh")
    commandLine("bash", script.absolutePath)
    // Vorher nur bei EFDN-Gong.mp3 → CI/Builds ohne exakt diese Datei hatten kein res/raw,
    // FCM-Kanal rett_alarm_w_* fehlte → keine/zerschlagene Android-Alarm-Benachrichtigung.
    onlyIf { project.file("../../voices").isDirectory }
}
tasks.named("preBuild").configure { dependsOn(syncAlarmSounds) }
