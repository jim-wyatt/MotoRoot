# Rebuild the Android helpers

The included DEX files are small original Java programs, not downloaded root exploits. Their Java sources are alongside them. UpdateHelper invokes Android's UpdateEngine API; UpdaterCleanup invokes alarm and notification APIs for the Motorola updater.

The reference PC used Microsoft OpenJDK 21 and Google's R8 8.3.37:

- [Microsoft OpenJDK downloads](https://learn.microsoft.com/en-us/java/openjdk/download)
- [Google R8 8.3.37 JAR](https://dl.google.com/dl/android/maven2/com/android/tools/r8/8.3.37/r8-8.3.37.jar)

Using your own installation paths, compile each class separately. An Android SDK JAR is not needed because the helpers use Java reflection.

```powershell
$JdkBin = 'C:\path\to\jdk-21\bin'
$R8 = 'C:\path\to\r8-8.3.37.jar'
& "$JdkBin\javac.exe" --release 8 .\UpdateHelper.java
New-Item -ItemType Directory -Force .\build-update | Out-Null
& "$JdkBin\java.exe" -cp $R8 com.android.tools.r8.D8 --min-api 26 --output .\build-update .\UpdateHelper.class
Copy-Item .\build-update\classes.dex .\UpdateHelper.dex

& "$JdkBin\javac.exe" --release 8 .\UpdaterCleanup.java
New-Item -ItemType Directory -Force .\build-cleanup | Out-Null
& "$JdkBin\java.exe" -cp $R8 com.android.tools.r8.D8 --min-api 26 --output .\build-cleanup .\UpdaterCleanup.class
Copy-Item .\build-cleanup\classes.dex .\UpdaterCleanup.dex
```

Java can print an obsolete source/target warning for release 8; the reference compile completed successfully. Never run an API-changing command merely to test compilation. The inspect argument prints method signatures without requesting an update reset or alarm cancellation.

Use UpdateHelper as root. Use UpdaterCleanup as the updater app's own numeric UID, discovered on the target phone. Make the pushed DEX read-only before running it as an app UID; Android rejects a writable DEX in that situation. Do not hard-code someone else's UID.
