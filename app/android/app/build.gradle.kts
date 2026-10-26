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

// Ключ ЗАГРУЗКИ в Google Play (android/upload.properties, тоже вне git).
// Play требует, чтобы ключ загрузки отличался от ключа подписи приложения:
// AAB подписывается им, а пользователю APK переподписывает сам Play — нашим
// же ключом выпуска, копию которого ему отдали через PEPK. Поэтому сборки из
// Play и с GitHub подписаны одинаково и обновляют друг друга.
val uploadProperties = Properties()
val uploadPropertiesFile = rootProject.file("upload.properties")
if (uploadPropertiesFile.exists()) {
    uploadProperties.load(uploadPropertiesFile.inputStream())
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

    buildFeatures {
        // BuildConfig.FLAVOR — Kotlin-сторона узнаёт, для какого магазина
        // собрана копия (см. PlatformChannels: установка APK только в github).
        buildConfig = true
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
        if (uploadPropertiesFile.exists()) {
            create("upload") {
                keyAlias = uploadProperties["keyAlias"] as String
                keyPassword = uploadProperties["keyPassword"] as String
                storeFile = uploadProperties["storeFile"]?.let { file(it) }
                storePassword = uploadProperties["storePassword"] as String
            }
        }
    }

    // ⚠️ ДВЕ СБОРКИ ОДНОГО ПРИЛОЖЕНИЯ: пакет, подпись и данные общие.
    //
    //  github — APK с сайта и GitHub, умеет обновляться сама (подписанный
    //           манифест, REQUEST_INSTALL_PACKAGES — src/github/AndroidManifest).
    //  play   — AAB для Google Play. Правило Play «Device and Network Abuse»:
    //           приложение из Play не обновляет себя ничем, кроме Play, и
    //           разрешение на установку пакетов ради самообновления не выдают.
    //           Поэтому в этой сборке нет ни разрешения, ни закачки.
    //
    // Dart узнаёт сборку по константе FLUTTER_APP_FLAVOR (её задаёт
    // `flutter build … --flavor <имя>`), см. core/app_store.dart.
    flavorDimensions += "store"
    productFlavors {
        create("github") {
            dimension = "store"
            isDefault = true
            signingConfig = signingConfigs.findByName("release")
        }
        create("play") {
            dimension = "store"
            // Код версии AAB = код arm64-APK с GitHub (Flutter для --split-per-abi
            // даёт arm64 = 2000 + N). Голый N из pubspec оказался бы МЕНЬШЕ
            // кода уже установленного с GitHub APK, и Play не смог бы обновить
            // его никогда — Android не ставит пакет с меньшим кодом поверх.
            versionCode = 2000 + flutter.versionCode
            // Ключ ЗАГРУЗКИ: Play проверяет им, что AAB от нас, и переподписывает
            // APK для людей ключом выпуска (копия у Play через PEPK).
            signingConfig = signingConfigs.findByName("upload")
        }
    }

    // Ядро (cores.aar) есть только под arm64-v8a и x86_64. Плагин jni приносит
    // ещё armeabi-v7a, и по ней Play раздавал бы приложение 32-битным
    // телефонам, где туннель не поднимется никогда. `ndk.abiFilters` у
    // флейвора не помогает: Flutter добавляет все ABI в defaultConfig, и
    // фильтры складываются. Сборки GitHub это не меняет: --split-per-abi с
    // --target-platform armeabi-v7a не собирает вовсе.
    packaging {
        jniLibs { excludes += "lib/armeabi-v7a/**" }
    }

    buildTypes {
        release {
            // ⚠️ РЕЛИЗ БЕЗ КЛЮЧА — ЭТО ОШИБКА СБОРКИ, А НЕ «СОБЕРЁМ ОТЛАДОЧНЫМ».
            //
            // Раньше здесь стоял молчаливый откат на debug-ключ. На чистой
            // машине (файл в .gitignore) `flutter build apk --release` выпускал
            // нормально выглядящий APK с ОБЩЕИЗВЕСТНОЙ подписью. Последствия
            // необратимы: такой APK нельзя обновить настоящим релизом — только
            // снос с потерей всех данных пользователя, — а «обновление» для
            // него может собрать кто угодно.
            //
            // Сборка теперь падает с внятным текстом. Это осознанная смена
            // поведения: команды, которые раньше «проходили», начнут ругаться —
            // и это лучше, чем узнать о подмене подписи после раздачи.
            //
            // ⚠️ Проверка — в задаче github-релиза (ниже), а не здесь. Блок
            // `release {}` исполняется при КОНФИГУРАЦИИ любой задачи, и на
            // чистой машине без ключа падали даже `flutter run` / `--debug`,
            // а сборка для Play требовала чужой ей ключ выпуска (аудит
            // 25.10.2026, J).
            //
            // Подпись задаёт СБОРКА (productFlavors выше), а не тип: подпись
            // типа перекрыла бы сборку. github — ключ выпуска, play — загрузки.
        }
    }
}

// Релиз github без ключа выпуска вышел бы НЕПОДПИСАННЫМ (signingConfig сборки
// = null). Проверяем до упаковки, чтобы файл не появился вовсе.
tasks.configureEach {
    val githubRelease = name.contains("GithubRelease") &&
        (name.startsWith("package") || name.startsWith("assemble") ||
            name.startsWith("bundle") || name.startsWith("sign"))
    if (githubRelease) {
        doFirst {
            if (!keystorePropertiesFile.exists()) {
                throw GradleException(
                    "Нет android/key.properties — релизный APK подписывать нечем.\n" +
                    "Создайте файл с storeFile/storePassword/keyAlias/keyPassword " +
                    "(пути через прямые слэши) или собирайте --debug.\n" +
                    "Подпись ОТЛАДОЧНЫМ ключом запрещена: такой APK невозможно " +
                    "обновить настоящим релизом."
                )
            }
        }
    }
}

// AAB для Play без ключа загрузки вышел бы неподписанным — Play его не примет.
// Проверка в задаче, а не при конфигурации: иначе без upload.properties
// падала бы и обычная сборка github.
tasks.configureEach {
    if (name == "bundlePlayRelease" || name == "assemblePlayRelease") {
        doFirst {
            if (!uploadPropertiesFile.exists()) {
                throw GradleException(
                    "Нет android/upload.properties — сборку для Google Play подписывать нечем.\n" +
                    "Ключ загрузки: signing/silentgate-upload.jks."
                )
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

    // QR-код подписки (platform/QrScanner.kt): камера — готовая CaptureActivity,
    // картинка — ядро ZXing. Обе под Apache-2.0, совместимы с GPL-3.0.
    // ML Kit не взят: закрытый бинарь и зависимость от сервисов Google Play.
    implementation("com.journeyapps:zxing-android-embedded:4.3.0")
    implementation("com.google.zxing:core:3.5.3")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
