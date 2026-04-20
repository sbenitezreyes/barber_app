plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Add the Google services Gradle plugin
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.barberapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    useLibrary("org.apache.http.legacy")

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.barberapp"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "app"

    productFlavors {
        create("client") {
            dimension = "app"
            applicationId = "com.example.barberapp"
            resValue("string", "app_name", "YaCut")
        }
        create("barber") {
            dimension = "app"
            applicationId = "com.example.barberapp.barber"
            resValue("string", "app_name", "YaCut Barbero")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Import the Firebase BoM
    implementation(platform("com.google.firebase:firebase-bom:34.9.0"))

    // Add Firebase Analytics dependency
    implementation("com.google.firebase:firebase-analytics")

    // Add other Firebase dependencies as needed
    // For example: implementation("com.google.firebase:firebase-auth")
}
