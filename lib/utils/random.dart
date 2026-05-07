import 'dart:math';

const _chars =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
final _random = Random();

String generateRandomString(int len) {
  return List.generate(len, (_) => _chars[_random.nextInt(_chars.length)])
      .join();
}
