# {{name}}

An Android app (`{{package}}`), created with `aosp-academy new-app` for the aosp-academy phone: compileSdk and targetSdk {{compileSdk}}, minSdk {{minSdk}}, Android Gradle Plugin {{agp}}, Gradle {{gradle}} (the wrapper checks the distribution's SHA-256).

It needs `ANDROID_HOME` and `JAVA_HOME` (JDK 17 or newer), which `aosp-academy setup` sets for your user. Open the folder in Android Studio, or from a shell:

```sh
./gradlew assembleDebug                # build app/build/outputs/apk/debug/app-debug.apk
./gradlew installDebug                 # install it on the connected phone
./gradlew connectedDebugAndroidTest    # run the instrumented tests on the phone
```
