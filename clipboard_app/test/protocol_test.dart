import 'package:flutter_test/flutter_test.dart';
import 'package:clipboard_core/clipboard_core.dart';
void main(){
 test('Shared native/Dart encryption protocol vector',() async {
  final crypto=ClipboardCryptoService();
  await crypto.deriveKeyFromUsername('cross-platform-password','fixture-a');
  expect(crypto.decryptText('AAECAwQFBgcICQoLDv7L0NrdVkdC+ltn7/sFX4vg5WGuh4bQkgGbBb+qps5Osc3qiKfycWIUlJL3Zg=='),'Windows Mac 安卓 iPhone iPad');
  await crypto.deriveKeyFromUsername('wrong','fixture-a');
  expect(()=>crypto.decryptText('AAECAwQFBgcICQoLDv7L0NrdVkdC+ltn7/sFX4vg5WGuh4bQkgGbBb+qps5Osc3qiKfycWIUlJL3Zg=='),throwsA(anything));
 });
}
