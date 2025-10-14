

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.main"
    compileSdk = flutter.compileSdkVersion

    // ถ้ามี ndkVersion เดิมและต้องใช้จริง ค่อยใส่กลับ
    // ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.main"   // ต้องตรงกับ google-services.json
        minSdk = Integer.max(23, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        debug {
            // ระหว่างพัฒนา ปิด shrink ไปเลย
            isMinifyEnabled = false
            isShrinkResources = false
        }
        release {
            // ถ้าต้องการลดขนาดแอปตอน build release ให้เปิดคู่นี้
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    flutter {
        source = "../.."
    }

    dependencies {
        // ใช้ Firebase BOM จัดการเวอร์ชัน
        implementation(platform("com.google.firebase:firebase-bom:33.3.0"))
        implementation("com.google.firebase:firebase-analytics")
        // เพิ่มตามที่ต้องใช้:
        // implementation("com.google.firebase:firebase-auth")
        // implementation("com.google.firebase:firebase-firestore")
    }
}
