/// Route paths of the app. The app is served at the site root (Cloudflare Pages, base
/// href `/`), so the browser shows `/v1/menu/...` without a hash sign.
class AppRoutes {
  static const String menu = '/v1/menu';

  /// Public site (no session): overview, projects, science topics, architecture and contact.
  static const String home = '/v1/home';
  static const String homeProjects = '$home/projects';
  static const String homeScience = '$home/science';
  static const String homeArchitecture = '$home/architecture';
  static const String homeContact = '$home/contact';

  static String scienceTopic(String topic) => '$homeScience/$topic';

  static String embed(String project,String report,String dataset) => '/v1/embed/$project/$report/$dataset';

  static String project(String project) => '$menu/$project';

  static String report(String project, String report) => '$menu/$project/$report';

  static String dataset(String project, String report, String datasetId) =>
      '$menu/$project/$report/$datasetId';
}
