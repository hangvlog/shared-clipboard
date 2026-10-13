import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as hash_lib;
import 'package:pointycastle/export.dart';

/// AES-256-GCM 端到端加密服务
///
/// 与桌面端 TypeScript 的 CryptoService 保持完全一致的加密协议：
/// - 使用 PBKDF2 从密码 + 用户名派生 AES-256 密钥
/// - 加密格式: base64([12-byte IV][AES-GCM ciphertext + tag])
/// - SHA-256 哈希用于内容去重
class ClipboardCryptoService {
  static const int _pbkdf2Iterations = 100000;
  static const int _saltLength = 16;
  static const int _ivLength = 12;
  static const int _keyLength = 32; // 256 bits

  Uint8List? _keyBytes;
  final List<Uint8List> _legacyKeys = [];

  /// Read-only compatibility keys; never select an encryption mode.
  Future<void> addDecryptionPassword(String password, String username) async {
    final key = _pbkdf2DeriveKey(password, _deriveFixedSalt(username));
    if (!_legacyKeys.any(
      (existing) => base64Encode(existing) == base64Encode(key),
    )) {
      _legacyKeys.add(key);
    }
  }

  /// 是否已设置加密密钥
  bool get hasKey => _keyBytes != null || _legacyKeys.isNotEmpty;

  /// 从密码 + 用户名派生加密密钥（确定性，跨设备一致）
  ///
  /// 与桌面端 CryptoService.deriveKeyFromUsername() 完全对齐：
  /// salt = SHA-256(username) 取前 16 字节
  /// key = PBKDF2(password, salt, iterations=100000, keyLen=32)
  Future<void> deriveKeyFromUsername(String password, String username) async {
    final salt = _deriveFixedSalt(username);
    _keyBytes = _pbkdf2DeriveKey(password, salt);
  }

  /// 从已有的 salt（base64）恢复密钥
  Future<void> restoreKey(String password, String saltBase64) async {
    final salt = base64Decode(saltBase64);
    _keyBytes = _pbkdf2DeriveKey(password, Uint8List.fromList(salt));
  }

  /// 加密文本
  ///
  /// 输出格式与桌面端一致：base64([12-byte IV][AES-GCM ciphertext + 16-byte tag])
  String encryptText(String plaintext) {
    if (_keyBytes == null) throw StateError('加密密钥未设置');

    final iv = _generateRandomBytes(_ivLength);
    final plaintextBytes = utf8.encode(plaintext);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(_keyBytes!),
          128, // tag length in bits
          iv,
          Uint8List(0),
        ),
      );

    final ciphertext = cipher.process(Uint8List.fromList(plaintextBytes));

    // 拼接 IV + ciphertext（含 tag）
    final combined = Uint8List(iv.length + ciphertext.length);
    combined.setAll(0, iv);
    combined.setAll(iv.length, ciphertext);

    return base64Encode(combined);
  }

  /// 解密文本
  ///
  /// 输入格式与桌面端一致：base64([12-byte IV][AES-GCM ciphertext + tag])
  String decryptText(String encryptedBase64) {
    if (!hasKey) throw StateError('加密密钥未设置');

    final combined = base64Decode(encryptedBase64);
    final iv = Uint8List.fromList(combined.sublist(0, _ivLength));
    final ciphertext = Uint8List.fromList(combined.sublist(_ivLength));

    for (final key in [?_keyBytes, ..._legacyKeys]) {
      try {
        final cipher = GCMBlockCipher(AESEngine())
          ..init(
            false,
            AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)),
          );
        return utf8.decode(cipher.process(ciphertext));
      } catch (_) {
        // Mixed histories can contain more than one old password.
      }
    }
    throw StateError('此记录需要原加密密码');
  }

  /// 生成文本内容的 SHA-256 哈希（用于加密场景下服务端去重）
  ///
  /// 与桌面端 generateContentHash() 完全一致
  static String generateContentHash(String text) {
    final bytes = utf8.encode(text);
    final digest = hash_lib.sha256.convert(bytes);
    return digest.toString();
  }

  /// 生成图片数据的短哈希（取前 8 字节 hex，用于快速去重）
  ///
  /// 与桌面端 generateImageHash() 完全一致
  static String generateImageHash(Uint8List imageBytes) {
    final digest = hash_lib.sha256.convert(imageBytes);
    return digest.bytes
        .take(8)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// 清除密钥
  void clearKey() {
    _keyBytes = null;
    _legacyKeys.clear();
  }

  // ============================================
  // 内部方法
  // ============================================

  /// 从用户名生成确定性盐（与桌面端 deriveFixedSalt 一致）
  Uint8List _deriveFixedSalt(String username) {
    final digest = hash_lib.sha256.convert(utf8.encode(username));
    return Uint8List.fromList(digest.bytes.take(_saltLength).toList());
  }

  /// PBKDF2 密钥派生
  Uint8List _pbkdf2DeriveKey(String password, Uint8List salt) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, _pbkdf2Iterations, _keyLength));

    return pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
  }

  /// 生成密码学安全的随机字节
  Uint8List _generateRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(length, (_) => random.nextInt(256)),
    );
  }
}
