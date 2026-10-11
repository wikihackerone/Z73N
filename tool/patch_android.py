"""يعدّل مجلد android المولَّد تلقائياً (flutter create) ليدعم:
- صلاحيات الإشعارات POST_NOTIFICATIONS والبصمة
- صلاحيات التخزين الداخلي للنسخ الاحتياطي (MANAGE_EXTERNAL_STORAGE وغيرها)
- MainActivity من نوع FlutterFragmentActivity (مطلوب لـ local_auth)
- Desugaring (مطلوب لـ flutter_local_notifications) و appcompat
- ثيم AppCompat لنافذة البصمة
- minSdk = 24
- تفعيل أعلى معدل تحديث للشاشة (120 هرتز) في MainActivity
"""
import pathlib
import re

root = pathlib.Path('android')

# ---------- AndroidManifest ----------
mf = root / 'app/src/main/AndroidManifest.xml'
t = mf.read_text(encoding='utf-8')
perms = [
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.USE_BIOMETRIC',
    'android.permission.RECEIVE_BOOT_COMPLETED',
    'android.permission.VIBRATE',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.INTERNET',
]
add = ''.join(
    f'    <uses-permission android:name="{p}"/>\n' for p in perms if p not in t
)
# صلاحيات التخزين للنسخ الاحتياطي في مجلد على التخزين الداخلي
storage = [
    ('android.permission.MANAGE_EXTERNAL_STORAGE', ''),
    ('android.permission.READ_EXTERNAL_STORAGE', ' android:maxSdkVersion="32"'),
    ('android.permission.WRITE_EXTERNAL_STORAGE', ' android:maxSdkVersion="29"'),
]
add += ''.join(
    f'    <uses-permission android:name="{p}"{extra}/>\n'
    for p, extra in storage if p not in t
)
t = re.sub(r'(<manifest\b[^>]*>)', lambda m: m.group(1) + '\n' + add, t, count=1)
# أندرويد 10: الوصول للتخزين بالطريقة القديمة
if 'requestLegacyExternalStorage' not in t:
    t = re.sub(r'(<application\b)', r'\1 android:requestLegacyExternalStorage="true"', t, count=1)
t = re.sub(r'android:label="[^"]*"', 'android:label="RentPal"', t, count=1)
# مفتاح خرائط جوجل (يُمرَّر كمتغير بيئة GOOGLE_MAPS_API_KEY / GitHub secret)
import os
key = os.environ.get('GOOGLE_MAPS_API_KEY', '').strip() or 'MISSING_GOOGLE_MAPS_API_KEY'
if 'com.google.android.geo.API_KEY' not in t:
    t = t.replace('</application>',
        f'    <meta-data android:name="com.google.android.geo.API_KEY" android:value="{key}"/>\n    </application>', 1)
if key == 'MISSING_GOOGLE_MAPS_API_KEY':
    print('WARNING: GOOGLE_MAPS_API_KEY غير مضبوط - الخريطة ستظهر فارغة')
mf.write_text(t, encoding='utf-8')
print('manifest patched')

# ---------- MainActivity -> FlutterFragmentActivity ----------
for f in list(root.rglob('MainActivity.kt')) + list(root.rglob('MainActivity.java')):
    src = f.read_text(encoding='utf-8')
    m = re.search(r'package\s+([\w.]+)', src)
    pkg = m.group(1) if m else 'com.example.real_estate_app'
    if f.suffix == '.kt':
        f.write_text(
            f'package {pkg}\n\n'
            'import android.os.Build\n'
            'import android.os.Bundle\n'
            'import io.flutter.embedding.android.FlutterFragmentActivity\n\n'
            'class MainActivity : FlutterFragmentActivity() {\n'
            '    override fun onCreate(savedInstanceState: Bundle?) {\n'
            '        super.onCreate(savedInstanceState)\n'
            '        enableHighRefreshRate()\n'
            '    }\n\n'
            '    override fun onResume() {\n'
            '        super.onResume()\n'
            '        enableHighRefreshRate()\n'
            '    }\n\n'
            '    // يطلب أعلى معدل تحديث تدعمه الشاشة (90/120/144 هرتز) بنفس الدقة الحالية\n'
            '    @Suppress("DEPRECATION")\n'
            '    private fun enableHighRefreshRate() {\n'
            '        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return\n'
            '        try {\n'
            '            val disp = windowManager.defaultDisplay ?: return\n'
            '            val cur = disp.mode\n'
            '            val best = disp.supportedModes\n'
            '                .filter { it.physicalWidth == cur.physicalWidth && it.physicalHeight == cur.physicalHeight }\n'
            '                .maxByOrNull { it.refreshRate } ?: return\n'
            '            val lp = window.attributes\n'
            '            lp.preferredDisplayModeId = best.modeId\n'
            '            lp.preferredRefreshRate = best.refreshRate\n'
            '            window.attributes = lp\n'
            '        } catch (e: Throwable) {\n'
            '        }\n'
            '    }\n'
            '}\n',
            encoding='utf-8',
        )
    else:
        f.write_text(
            f'package {pkg};\n\n'
            'import android.os.Build;\n'
            'import android.os.Bundle;\n'
            'import android.view.Display;\n'
            'import android.view.WindowManager;\n'
            'import io.flutter.embedding.android.FlutterFragmentActivity;\n\n'
            'public class MainActivity extends FlutterFragmentActivity {\n'
            '    @Override\n'
            '    protected void onCreate(Bundle savedInstanceState) {\n'
            '        super.onCreate(savedInstanceState);\n'
            '        enableHighRefreshRate();\n'
            '    }\n\n'
            '    @Override\n'
            '    protected void onResume() {\n'
            '        super.onResume();\n'
            '        enableHighRefreshRate();\n'
            '    }\n\n'
            '    @SuppressWarnings("deprecation")\n'
            '    private void enableHighRefreshRate() {\n'
            '        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return;\n'
            '        try {\n'
            '            Display disp = getWindowManager().getDefaultDisplay();\n'
            '            Display.Mode cur = disp.getMode();\n'
            '            Display.Mode best = null;\n'
            '            for (Display.Mode m : disp.getSupportedModes()) {\n'
            '                if (m.getPhysicalWidth() == cur.getPhysicalWidth() && m.getPhysicalHeight() == cur.getPhysicalHeight()\n'
            '                        && (best == null || m.getRefreshRate() > best.getRefreshRate())) best = m;\n'
            '            }\n'
            '            if (best == null) return;\n'
            '            WindowManager.LayoutParams lp = getWindow().getAttributes();\n'
            '            lp.preferredDisplayModeId = best.getModeId();\n'
            '            lp.preferredRefreshRate = best.getRefreshRate();\n'
            '            getWindow().setAttributes(lp);\n'
            '        } catch (Throwable ignored) {\n'
            '        }\n'
            '    }\n'
            '}\n',
            encoding='utf-8',
        )
    print('MainActivity patched:', f)

# ---------- app/build.gradle(.kts) ----------
kts = root / 'app/build.gradle.kts'
groovy = root / 'app/build.gradle'
if kts.exists():
    g = kts
    txt = g.read_text(encoding='utf-8')
    txt = re.sub(r'(compileOptions\s*\{)',
                 lambda m: m.group(1) + '\n        isCoreLibraryDesugaringEnabled = true', txt, count=1)
    txt = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24', txt)
    txt += (
        '\ndependencies {\n'
        '    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n'
        '    implementation("androidx.appcompat:appcompat:1.7.0")\n'
        '}\n'
    )
else:
    g = groovy
    txt = g.read_text(encoding='utf-8')
    txt = re.sub(r'(compileOptions\s*\{)',
                 lambda m: m.group(1) + '\n        coreLibraryDesugaringEnabled true', txt, count=1)
    txt = re.sub(r'minSdk(Version)?\s*=?\s*flutter\.minSdkVersion', 'minSdkVersion 24', txt)
    txt += (
        '\ndependencies {\n'
        "    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n"
        "    implementation 'androidx.appcompat:appcompat:1.7.0'\n"
        '}\n'
    )
g.write_text(txt, encoding='utf-8')
print('gradle patched:', g)

# ---------- ثيم AppCompat (نافذة البصمة) ----------
for sx in root.glob('app/src/main/res/values*/styles.xml'):
    s = sx.read_text(encoding='utf-8')
    s2 = re.sub(r'parent="@android:style/Theme\.[\w.]+"',
                'parent="Theme.AppCompat.DayNight.NoActionBar"', s)
    if s2 != s:
        sx.write_text(s2, encoding='utf-8')
        print('styles patched:', sx)


# ---------- رفع compileSdk لكل الإضافات (حل خطأ checkReleaseAarMetadata) ----------
# بعض الإضافات (مثل file_picker) تُبنى على android-34 بينما flutter_plugin_android_lifecycle تتطلب 36+
root_kts = root / 'build.gradle.kts'
root_groovy = root / 'build.gradle'
KTS_FIX = """

// --- رفع compileSdk لإضافات فلاتر القديمة إلى 36 ---
subprojects {
    fun bumpCompileSdk(p: Project) {
        if (p.name == "app") return
        val ext = p.extensions.findByName("android") ?: return
        try {
            val cur = ext.javaClass.methods
                .firstOrNull { it.name == "getCompileSdk" && it.parameterCount == 0 }
                ?.invoke(ext) as? Int
            if (cur != null && cur >= 36) return
            val setter = ext.javaClass.methods
                .firstOrNull { it.name == "setCompileSdk" && it.parameterCount == 1 }
            if (setter != null) {
                setter.invoke(ext, 36)
            } else {
                ext.javaClass.methods
                    .firstOrNull {
                        it.name == "compileSdkVersion" && it.parameterTypes.size == 1 &&
                            it.parameterTypes[0] == Int::class.javaPrimitiveType
                    }
                    ?.invoke(ext, 36)
            }
        } catch (e: Throwable) {
        }
    }
    if (state.executed) bumpCompileSdk(this) else afterEvaluate { bumpCompileSdk(this) }
}
"""
GROOVY_FIX = """

// --- رفع compileSdk لإضافات فلاتر القديمة إلى 36 ---
subprojects { p ->
    def bump = {
        if (p.name != 'app' && p.hasProperty('android')) {
            try { p.android.compileSdkVersion 36 } catch (Throwable ignored) { }
        }
    }
    if (p.state.executed) { bump() } else { p.afterEvaluate { bump() } }
}
"""
if root_kts.exists():
    t = root_kts.read_text(encoding='utf-8')
    if 'bumpCompileSdk' not in t:
        root_kts.write_text(t + KTS_FIX, encoding='utf-8')
    print('root gradle (kts) patched: compileSdk 36 for plugins')
elif root_groovy.exists():
    t = root_groovy.read_text(encoding='utf-8')
    if 'bump = {' not in t:
        root_groovy.write_text(t + GROOVY_FIX, encoding='utf-8')
    print('root gradle (groovy) patched: compileSdk 36 for plugins')


# ---------- مفتاح توقيع ثابت ----------
# كل تشغيل على GitHub يولّد مفتاح debug جديداً، فلا يمكن تحديث التطبيق فوق النسخة السابقة.
# نضع مفتاحاً ثابتاً من المستودع مكان مفتاح debug ليُوقَّع كل APK بنفس التوقيع.
import shutil
ks = pathlib.Path('tool/rentpal-debug.keystore')
if ks.exists():
    dst = pathlib.Path.home() / '.android'
    dst.mkdir(parents=True, exist_ok=True)
    shutil.copy(ks, dst / 'debug.keystore')
    print('stable signing keystore installed')
