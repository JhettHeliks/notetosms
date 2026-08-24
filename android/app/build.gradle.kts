plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.notetosms.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.notetosms.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signing with the debug keys for local testing, replace with release signing for production keystore.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    applicationVariants.all {
        val variant = this
        variant.outputs.all {
            val output = this
            if (output is com.android.build.gradle.internal.api.BaseVariantOutputImpl) {
                val vName = variant.versionName ?: "1.0.0"
                val bType = variant.buildType.name
                val abi = output.getFilter(com.android.build.OutputFile.ABI)
                val abiSuffix = if (abi != null) "-$abi" else ""
                output.outputFileName = "notetosms-v${vName}-${bType}${abiSuffix}.apk"
            }
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
}

flutter {
    source = "../.."
}
