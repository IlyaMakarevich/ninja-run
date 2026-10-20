plugins {
    id("com.android.application")
}

android {
    namespace = "com.makarevich.ninjarun"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.makarevich.ninjarun"
        minSdk = 28
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
