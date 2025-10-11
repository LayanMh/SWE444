plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") // apply here
}

android {
    namespace = "com.example.absherk"
    compileSdk = 36 // or flutter.compileSdkVersion if using Flutter DSL

    defaultConfig {
        applicationId = "com.example.absherk"
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
        manifestPlaceholders["appAuthRedirectScheme"] = "msauth"
        minSdkVersion 21
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        coreLibraryDesugaringEnabled true
    }

    kotlinOptions {
        jvmTarget = "11"
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
    // Firebase BoM
    implementation(platform("com.google.firebase:firebase-bom:34.3.0"))

    // Firebase products
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-firestore")

    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.0.4"
}
