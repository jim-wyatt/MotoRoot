plugins {
    id("com.android.application")
}

android {
    namespace = "{{package}}"
    compileSdk = {{compileSdk}}
    buildToolsVersion = "{{buildTools}}"

    defaultConfig {
        applicationId = "{{package}}"
        minSdk = {{minSdk}}
        targetSdk = {{targetSdk}}
        versionCode = 1
        versionName = "0.1"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    androidTestImplementation("androidx.test:runner:{{androidxTestRunner}}")
    androidTestImplementation("androidx.test:core:{{androidxTestCore}}")
    androidTestImplementation("androidx.test.ext:junit:{{androidxTestExtJunit}}")
}
