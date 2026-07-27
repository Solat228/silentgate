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
    // Ядро собирается из исходников через gomobile и НЕ коммитится — как
    // xray.exe/sing-box.exe на Windows. Рецепт: tools/build-android-cores.md.
    //
    // libbox = sing-box (GPL-3.0): TUN, маршрутизация, DNS и сами протоколы
    // (VLESS/Reality, Trojan, Shadowsocks, Hysteria2).
    //
    // ⚠️ libxray.aar собран, но НЕ подключён: два gomobile-AAR несут по своей
    // копии Go-рантайма (go.Seq) и валят сборку конфликтом классов. Пока это
    // не решено объединением обоих ядер в один модуль, панельные профили
    // «Авто» (готовые Xray-конфиги) на Android недоступны.
    implementation(files("libs/libbox.aar"))
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
