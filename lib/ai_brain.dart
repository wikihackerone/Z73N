import 'dart:io';

import 'package:llamadart/llamadart.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// نموذج Qwen 2.5 (0.5B) المضغوط Q4_K_M — أخف نموذج مناسب ويدعم العربي.
/// يُنزَّل مرة واحدة (~491 ميجا) ثم يعمل بالكامل أوفلاين على الهاتف.
const kAiModelUrl =
    'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf';
const kAiModelFile = 'qwen2.5-0.5b-instruct-q4_k_m.gguf';
const int kAiModelMinBytes = 400 * 1024 * 1024; // للتأكد أن التنزيل كامل
const kAiModelSizeText = '491 ميجا';

class _Cancelled implements Exception {
  const _Cancelled();
}

/// «العقل» الذكي: يحوّل سؤالك بأي صياغة إلى أمر محدد يفهمه المساعد.
/// لا يحسب أرقاماً ولا يرد من عنده؛ الحسابات كلها من قاعدة بياناتك.
class AiBrain {
  AiBrain._();
  static final AiBrain I = AiBrain._();

  LlamaEngine? _engine;
  bool _cancel = false;

  Future<File> _file() async {
    final d = await getApplicationSupportDirectory();
    return File(p.join(d.path, 'ai', kAiModelFile));
  }

  Future<bool> installed() async {
    final f = await _file();
    return f.existsSync() && f.lengthSync() >= kAiModelMinBytes;
  }

  void cancelDownload() => _cancel = true;

  /// تنزيل النموذج مع نسبة التقدم (0..1). يرمي استثناء عند الفشل أو الإلغاء.
  Future<void> download(void Function(double) onProgress) async {
    _cancel = false;
    final f = await _file();
    await f.parent.create(recursive: true);
    final part = File('${f.path}.part');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(Uri.parse(kAiModelUrl));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode}');
      }
      final total = res.contentLength;
      final sink = part.openWrite();
      var got = 0;
      try {
        await for (final chunk in res) {
          if (_cancel) throw const _Cancelled();
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) onProgress(got / total);
        }
      } finally {
        await sink.close();
      }
      if (got < kAiModelMinBytes) throw Exception('التنزيل غير مكتمل');
      if (f.existsSync()) await f.delete();
      await part.rename(f.path);
    } catch (_) {
      try {
        if (part.existsSync()) await part.delete();
      } catch (_) {}
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<void> remove() async {
    await dispose();
    final f = await _file();
    if (f.existsSync()) await f.delete();
  }

  Future<void> dispose() async {
    final e = _engine;
    _engine = null;
    try {
      await e?.dispose();
    } catch (_) {}
  }

  Future<LlamaEngine> _load() async {
    final e = _engine;
    if (e != null) return e;
    final path = (await _file()).path;
    LlamaEngine eng;
    try {
      eng = await LlamaEngine.load(LlamaModel(ModelSource.parse(path)));
    } catch (_) {
      eng = await LlamaEngine.load(LlamaModel(ModelSource.parse('file://$path')));
    }
    return _engine = eng;
  }

  /// يرجع رد النموذج الخام (أمر واحد) أو null عند أي فشل
  Future<String?> classify(String question, List<String> names) async {
    try {
      final eng = await _load();
      final prompt = '''You are a command classifier inside a property-rental app.
Read the user's question (Arabic) and answer with exactly ONE command from the list, and nothing else.
DEBTORS = who owes money / late payments
UPCOMING = rent that will be due soon
COLLECTED_MONTH = money collected this month
COLLECTED_LAST = money collected last month
COLLECTED_YEAR = money collected this year
VACANT = empty / vacant properties
CONTRACTS_EXPIRING = contracts about to end
CREDITS = tenants who paid extra
LAST_PAYMENTS = latest receipts
SUMMARY = general summary
ID_CARD:<name> = national ID card images of a tenant
CONTRACT_DOC:<name> = contract images of a tenant
ACCOUNT:<name> = account details of a tenant or property
Known names: ${names.join(', ')}
If nothing matches answer NONE.
Question: $question
Command:''';
      final reply = await eng
          .create(
            [LlamaChatMessage.fromText(role: LlamaChatRole.user, text: prompt)],
            params: const GenerationParams(maxTokens: 24),
          )
          .text();
      return reply.trim();
    } catch (_) {
      return null;
    }
  }
}
