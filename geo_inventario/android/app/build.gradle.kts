plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {

    namespace = "com.example.geo_inventario"
    compileSdk = flutter.compileSdkVersion

    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "com.example.geo_inventario"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
    }
}


flutter {
    source = "../.."
}
