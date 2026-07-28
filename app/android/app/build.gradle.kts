import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Подпись релиза: ключи берутся из android/key.properties, которого НЕТ в
// репозитории (см. .gitignore). Если файла нет — релиз подписывается отладочным
// ключом, чтобы `flutter build apk` работал у любого разработчика.
// ⚠️ Потеря релизного keystore = невозможность обновления у всех, кто поставил
// APK со стороны (задача 70 плана docs/platforms/ANDROID.md).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "lol.silentgate"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "lol.silentgate"
        // minSdk 24: ниже нет ни VpnService в нужном виде, ни разумной доли
        // устройств. Блокировка ПРИЛОЖЕНИЙ требует API 29+ и гейтится в UI
        // отдельно (§1.2 плана).
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

    }

    // ⚠️ СПИСОК ABI ЗАДАЁТСЯ НЕ ЗДЕСЬ, А ФЛАГОМ СБОРКИ:
    //
    //   flutter build apk --release --split-per-abi \
    //           --target-platform android-arm64,android-x64
    //
    // Ядро (`libs/cores.aar`) собрано только под arm64-v8a и x86_64 — см.
    // tools/build-android-cores.md. Без этого флага выпускается ещё и
    // armeabi-v7a: APK на 18 МБ, в котором libcores.so ОТСУТСТВУЕТ. Он
    // устанавливается, открывается и выглядит рабочим, а туннель не
    // поднимается никогда.
    //
    // Ни `defaultConfig.ndk.abiFilters`, ни блок `splits { abi { … } }` здесь
    // не работают: Flutter конфигурирует splits сам и перекрывает наш блок, а
    // при одновременном использовании Gradle падает — «Conflicting
    // configuration … cannot be present when splits abi filters are set».

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    // ОДИН AAR с ОБОИМИ ядрами. Раздельные libbox.aar и libxray.aar собрать
    // можно, но подключить вместе нельзя: каждый gomobile-AAR несёт свою копию
    // Go-рантайма, и сборка падает на «Duplicate class go.Seq». Общий модуль
    // (tools/build-android-cores.md) снимает конфликт и заодно экономит: 18 МБ
    // против 25 МБ по отдельности.
    //
    //   libbox  — sing-box (GPL-3.0): TUN, маршрутизация, DNS, hysteria2;
    //   libXray — Xray-core (MPL-2.0) через обёртку libXray (MIT): панельные
    //             профили «Авто» с balancers/burstObservatory, которые
    //             sing-box переварить не может.
    implementation(files("libs/cores.aar"))
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
