import 'package:web/web.dart' as web;

void openBrowserWindow(String url) {
  web.window.open(url, '_blank', 'noopener,noreferrer');
}
