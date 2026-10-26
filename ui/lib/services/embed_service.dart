import 'report_service.dart';

/// Uses the same descriptor contract for the Share dialog and API clients.
Future<Map<String, dynamic>> itemEmbed(
  String path, {
  required String language,
  String? theme,
}) {
  final uri = Uri.parse(path);
  final parts = uri.pathSegments;
  if (parts.length != 5 || parts[0] != 'v1' || parts[1] != 'menu') {
    return Future.error(
      ArgumentError('Only an individual chart or table can be embedded.'),
    );
  }
  return ReportService.instance.api.getJson(
    '/projects/${Uri.encodeComponent(parts[2])}/showcase/${Uri.encodeComponent(parts[3])}/cards/${Uri.encodeComponent(parts[4])}/embed',
    {'lang': language, 'theme': ?theme, ...uri.queryParameters},
  );
}
