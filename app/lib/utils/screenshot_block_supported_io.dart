import 'dart:io';

bool isScreenshotBlockSupported() =>
    Platform.isAndroid || Platform.isIOS;
