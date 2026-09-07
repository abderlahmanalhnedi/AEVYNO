# ابدأ من هنا — تعليمات مالك المشروع

هذه الحزمة مصممة لتُرفع إلى **ChatGPT Project** وتُستخدم أيضًا داخل repository مع **Codex**.

## الفكرة

تطبيق IPTV / Media Client عالي الجودة لمنظومة Apple، مع تركيز أساسي على **Apple TV** ثم iPhone/iPad، وبعد الاستقرار يمكن إضافة macOS.

أهم متطلبات المشروع ليست كثرة الميزات، بل:

1. التصميم ممتاز جدًا ويشعر المستخدم أنه تطبيق Apple حقيقي.
2. السرعة عالية حتى مع مكتبات IPTV ضخمة.
3. تشغيل الفيديو مستقر ومتوافق قدر الإمكان.
4. Continue Watching والمفضلة والإعدادات المناسبة تتزامن بين الأجهزة عبر iCloud.
5. الكود منظم وقابل للتطوير ولا يتحول إلى مشروع معقد وغير قابل للصيانة.

## كيف تستخدم الملفات

### داخل ChatGPT Projects

ارفع جميع الملفات الموجودة في هذه الحزمة. ثم انسخ محتوى `CHATGPT_PROJECT_INSTRUCTIONS.md` إلى Project Instructions إن كانت الواجهة تسمح بذلك.

### داخل Codex / Git repository

ضع `AGENTS.md` في **جذر الـrepository**. هذا أهم ملف بالنسبة لـCodex ويجب ألا يُحذف.

الملف `codex-skill/apple-iptv-engineering/SKILL.md` هو Skill اختيارية قابلة لإعادة الاستخدام عندما تكون Skills متاحة في بيئة Codex التي تستخدمها. حتى بدون تثبيت Skill، يبقى `AGENTS.md` هو المرجع الإجباري داخل الـrepo.

## أول أمر أرسله إلى Codex

بعد إنشاء repo ونسخ هذه الملفات إليه، استخدم النص الموجود حرفيًا في:

`FIRST_CODEX_PROMPT.md`

ولا تطلب منه مباشرة: "ابني التطبيق كامل". نحن نريد milestones صغيرة يمكن اختبارها.

## ترتيب المشروع الصحيح

- Phase 0: تأسيس Xcode project + targets + architecture + CI/build validation.
- Phase 1: tvOS shell + design system + focus + navigation + mock catalog.
- Phase 2: IPTV sources + parsing + local cache.
- Phase 3: playback foundation.
- Phase 4: Continue Watching + CloudKit.
- Phase 5: iPhone/iPad companion.
- Phase 6: EPG, subtitles, PiP, search, favorites refinement.
- Phase 7: compatibility hardening + large-library performance + TestFlight.

## قرارات ممنوعة بدون توثيق

Codex لا يحق له أن يقرر وحده استخدام Flutter/React Native، تغيير الـarchitecture، إضافة VLC/FFmpeg أو dependency كبيرة، تعطيل ATS بالكامل، تخزين password في CloudKit، أو نقل بيانات المكتبة الكبيرة إلى iCloud. أي تغيير من هذا النوع يحتاج ADR جديد ومبرر واضح واختبارات.

## مبدأ مهم

الـSimulator مفيد للتطوير، لكنه **ليس إثباتًا** أن تجربة Apple TV ممتازة. الـFocus، Siri Remote، الأداء، الذاكرة، startup، playback، subtitles، وnetwork recovery يجب اختبارها دوريًا على Apple TV حقيقي.
