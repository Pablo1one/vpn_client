# libbox (sing-box / форк amnezia-box, собран gomobile) — классы и методы зовутся
# из нативного Go по JNI-именам, обфускация сломает биндинг
-keep class io.nekohasekai.libbox.** { *; }
-keep interface io.nekohasekai.libbox.** { *; }
-dontwarn io.nekohasekai.**

# gomobile runtime (go.Seq и прокси-классы интерфейсов)
-keep class go.** { *; }
-dontwarn go.**

# наши классы реализуют интерфейсы libbox (PlatformInterface / CommandServerHandler /
# CommandClientHandler) и вызываются из Go по именам методов — не переименовывать
-keep class lightningmcqueen.proxy.** { *; }

# Flutter engine/embedding
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**
