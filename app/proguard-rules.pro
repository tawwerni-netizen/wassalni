# kotlinx.serialization: the plugin generates serializers reflectively resolved
# by name, so the companion Companion.serializer() entry points must survive.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**

-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}

-keep,includedescriptorclasses class com.wassalni.**$$serializer { *; }
-keepclassmembers class com.wassalni.** {
    *** Companion;
}
-keepclasseswithmembers class com.wassalni.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Ktor / OkHttp engine selection is reflective.
-dontwarn org.slf4j.**
-dontwarn io.ktor.**
-keepclassmembers class io.ktor.** { volatile <fields>; }

# Supabase realtime + postgrest models
-keep class io.github.jan.supabase.** { *; }
-dontwarn io.github.jan.supabase.**

# Credential Manager's Play Services backend is loaded reflectively and only
# needed on devices that actually have it.
-if class androidx.credentials.CredentialManager
-keep class androidx.credentials.playservices.** {
  *;
}
