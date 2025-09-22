plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") // apply here
}

android {
    namespace = "com.example.absherk"
    compileSdk = 35 // or flutter.compileSdkVersion if using Flutter DSL

    defaultConfig {
        applicationId = "com.example.absherk"
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
        manifestPlaceholders["appAuthRedirectScheme"] = "msauth"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
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
}
