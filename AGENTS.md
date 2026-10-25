# AGENTS.md — MooDfacebook

## اللغة / Language

- **تحدَّث مع المستخدم باللغة العربية دائماً.** المستخدم صاحب المشروع عربي،
  وطلب صراحةً أن تكون كل الردود والتقارير بالعربية ليتمكن من متابعتها.
- الكود والأسماء والمعرّفات ورسائل الـ commit تبقى بالإنجليزية كما هي.
  الشرح والملخصات والأسئلة تكون بالعربية.
- يمكن استخدام المصطلحات التقنية الإنجليزية (hook, tweak, dylib, respring…)
  كما هي داخل النص العربي، فهذا أوضح من ترجمتها.

## المشروع

A RootHide Theos tweak for Facebook (`com.facebook.Facebook`), iOS 18.x / arm64e.

- المصدر الأساسي: `Tweak.x` (ملف واحد).
- `control` يحمل بيانات الحزمة، و`MooDfacebook.plist` فلتر MobileLoader.
- المفضّلات (prefs) تُحفظ في مجموعة `NSUserDefaults` باسم
  `com.mody-iq.moodfacebook`، وكل ميزة لها مفتاح خاص بها.

## البناء / Build

```sh
export THEOS=/workspace/theos
export PATH="$THEOS/toolchain/linux/iphone/bin:$PATH"
make all                      # تحقّق من التصريف (يجب 0 errors)
make package FINALPACKAGE=1   # إنتاج ملف .deb
```

ملاحظات مهمّة عند البناء محلياً:

- يجب البناء في مجلد خارج `/workspace/project` (مثل `/tmp/mdfbuild`)
  لأن صلاحية setgid على مجلد المشروع تُفشل خطوة staging في Theos.
- تحذير `ld: ... incompatible arm64e ABI compiler` حميد ولا يعني وجود خطأ.
- البناء يستهدف arm64e فقط، ويجب أن يبقى كذلك.

## قواعد الكود

- Arc مُفعَّل (`-fobjc-arc`).
- كل ميزة تُقرأ من إعدادات المستخدم عبر `MDFPref(key, default)` — لا قيم
  مثبّتة داخل الـ hooks.
- عند إضافة ميزة جديدة: أضف مفتاحها في `MDFRegisterDefaults`، ثم صفّاً في
  `buildModel`، ثم اقرأ المفتاح في الـ hook المعني.

## دروس تعلّمناها (لا تُعِد الأخطاء نفسها)

1. **نافذة شفافة لا يجب أن تبتلع اللمسات.** يجب أن ترجع `hitTest:` القيمة
   `nil` عن النافذة نفسها وعن جذرها، وإلا تجمّد التطبيق تحت النافذة.
   استخدم `MDFPassthroughWindow` ولا تستخدم `UIWindow` مباشرة.
2. **الزر العائم** لا يعتمد على ضغط مطوّل: فيسبوك يثبّت مُعرِّفات ضغط خاصة به
   على الـ feed وتربح الـ gesture arena. الاعتماد على الزر العائم + النقر
   الثلاثي فقط.
3. **إخفاء طبقة Reels** يجب ألا يلمس أي شجرة تحتوي `AVPlayerLayer`، وإلا
   ظهرت شاشة سوداء.
4. **حفظ الصور** لا يستخدم `UIImageWriteToSavedPhotosAlbum` لأن Info.plist
   في فيسبوك لا يحتوي وصف صلاحية مكتبة الصور فيرتفع استثناء ويسقط التطبيق.
5. عند تعديل `Tweak.x` شغّل `make all` وتأكّد من 0 errors قبل الـ commit.
