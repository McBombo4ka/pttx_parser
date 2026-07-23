# Игнорировать предупреждения для Sceneform (ARCore)
-dontwarn com.google.ar.sceneform.**
-keep class com.google.ar.sceneform.** { *; }

# Игнорировать предупреждения для Google Desugar Runtime
-dontwarn com.google.devtools.build.android.desugar.runtime.**