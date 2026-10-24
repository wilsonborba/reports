/// Catalog models (API: /catalog, /projects/{project}, /projects/{project}/reports).
/// Everything about a project (texts, links, colors, images) comes from the API.
library;

/// Logo or icon of a project (API `assets`).
class AssetRef {
  final String url;
  final int width;
  final int height;

  const AssetRef({required this.url, required this.width, required this.height});

  factory AssetRef.fromJson(Map<String, dynamic> j) =>
      AssetRef(url: '${j['url']}', width: (j['width'] as num?)?.toInt() ?? 0, height: (j['height'] as num?)?.toInt() ?? 0);

  Map<String, dynamic> toJson() => {'url': url, 'width': width, 'height': height};
}

/// A link, category, statistic or collaborator of a project in domain_api.
class DomainLink {
  final String type;
  final String url;
  final String? icon;
  const DomainLink(this.type, this.url, this.icon);
}

class DomainCategory {
  final String category;
  final String item;
  const DomainCategory(this.category, this.item);
}

class DomainStatistic {
  final String name;
  final String value;
  const DomainStatistic(this.name, this.value);
}

class DomainCollaborator {
  final String name;
  final String? githubUsername;
  final String? avatarUrl;
  final String? role;
  const DomainCollaborator(this.name, {this.githubUsername, this.avatarUrl, this.role});
}

/// Project details that the engine composes from domain_api (presentation only; they
/// stay in the language domain_api sends).
class DomainDetails {
  final String id;
  final String slug;
  final String name;
  final String tagline;
  final String description;
  final String? status;
  final String? mainLink;
  final String? repositoryUrl;
  final String? coverUrl;
  final String fetchedAt;
  final List<DomainLink> links;
  final List<DomainCategory> categories;
  final List<DomainStatistic> statistics;
  final List<DomainCollaborator> collaborators;

  /// True when the detail block is the last-known copy (domain_api did not answer).
  final bool detailStale;

  /// False until the first background fetch of the slow detail route finished.
  final bool hasDetail;

  const DomainDetails({
    required this.id,
    required this.slug,
    required this.name,
    this.tagline = '',
    this.description = '',
    this.status,
    this.mainLink,
    this.repositoryUrl,
    this.coverUrl,
    this.fetchedAt = '',
    this.links = const [],
    this.categories = const [],
    this.statistics = const [],
    this.collaborators = const [],
    this.detailStale = false,
    this.hasDetail = false,
  });

  static List<T> _list<T>(dynamic v, T? Function(Map<String, dynamic>) f) => v is List
      ? [for (final e in v) if (e is Map) f(Map<String, dynamic>.from(e))].whereType<T>().toList()
      : <T>[];

  static DomainDetails? fromJson(dynamic j) {
    if (j is! Map) return null;
    final d = j['detail'];
    return DomainDetails(
      id: '${j['id'] ?? ''}',
      slug: '${j['slug'] ?? ''}',
      name: '${j['name'] ?? ''}',
      tagline: '${j['tagline'] ?? ''}',
      description: '${j['description'] ?? ''}',
      status: j['status'] as String?,
      mainLink: j['main_link'] as String?,
      repositoryUrl: j['repository_url'] as String?,
      coverUrl: j['cover_url'] as String?,
      fetchedAt: '${j['fetched_at'] ?? ''}',
      hasDetail: d is Map,
      detailStale: j['detail_stale'] == true,
      links: d is Map ? _list(d['links'], (m) => m['url'] == null ? null : DomainLink('${m['link_type'] ?? ''}', '${m['url']}', m['icon'] as String?)) : const [],
      categories: d is Map ? _list(d['categories'], (m) => DomainCategory('${m['category'] ?? ''}', '${m['item'] ?? ''}')) : const [],
      statistics: d is Map ? _list(d['statistics'], (m) => DomainStatistic('${m['name'] ?? ''}', '${m['value'] ?? ''}')) : const [],
      collaborators: d is Map
          ? _list(d['collaborators'],
              (m) => DomainCollaborator('${m['name'] ?? ''}', githubUsername: m['github_username'] as String?, avatarUrl: m['avatar_url'] as String?, role: m['role'] as String?))
          : const [],
    );
  }
}

class ProjectSummary {
  final String slug;
  final String name;

  /// Reports text when it exists, else the domain_api text.
  final String tagline;
  final String description;

  /// Product website, or the GitHub repository when the project has no domain.
  final String? websiteUrl;
  final String? repositoryUrl;
  final int reportCount;

  /// Theme tokens per mode (`light`, `dark`); a missing mode uses the fallback theme.
  final Map<String, Map<String, dynamic>> theme;

  /// Images by role. `logo` is the domain_api cover when the project has one.
  final Map<String, AssetRef> assets;

  /// fresh, stale, unavailable, missing or unlinked
  final String domainStatus;
  final DomainDetails? domain;

  const ProjectSummary({
    required this.slug,
    required this.name,
    required this.description,
    required this.reportCount,
    this.tagline = '',
    this.websiteUrl,
    this.repositoryUrl,
    this.theme = const {},
    this.assets = const {},
    this.domainStatus = 'unlinked',
    this.domain,
  });

  factory ProjectSummary.fromJson(Map<String, dynamic> j) {
    final theme = <String, Map<String, dynamic>>{};
    final t = j['theme'];
    if (t is Map) {
      for (final mode in ['light', 'dark']) {
        if (t[mode] is Map) theme[mode] = Map<String, dynamic>.from(t[mode] as Map);
      }
    }
    final domain = DomainDetails.fromJson(j['domain']);
    String pick(String own, String? fromDomain) => own.trim().isNotEmpty ? own : (fromDomain ?? '');
    return ProjectSummary(
      slug: j['slug'] as String,
      name: (j['name'] ?? j['slug']) as String,
      tagline: pick('${j['tagline'] ?? ''}', domain?.tagline),
      description: pick('${j['description'] ?? ''}', domain?.description),
      websiteUrl: (j['website_url'] as String?) ?? domain?.mainLink,
      repositoryUrl: (j['repository_url'] as String?) ?? domain?.repositoryUrl,
      reportCount: (j['report_count'] as num?)?.toInt() ?? 0,
      theme: theme,
      assets: {if (domain?.coverUrl != null) 'logo': AssetRef(url: domain!.coverUrl!, width: 0, height: 0)},
      domainStatus: '${j['domain_status'] ?? 'unlinked'}',
      domain: domain,
    );
  }

  /// Same fields as the API, so a stored copy reads back with [ProjectSummary.fromJson].
  Map<String, dynamic> toJson() => {
        'slug': slug,
        'name': name,
        'tagline': tagline,
        'description': description,
        'website_url': websiteUrl,
        'repository_url': repositoryUrl,
        'report_count': reportCount,
        'theme': theme,
        'domain_status': domainStatus,
        if (domain != null)
          'domain': {
            'id': domain!.id,
            'slug': domain!.slug,
            'name': domain!.name,
            'tagline': domain!.tagline,
            'description': domain!.description,
            'status': domain!.status,
            'main_link': domain!.mainLink,
            'repository_url': domain!.repositoryUrl,
            'cover_url': domain!.coverUrl,
            'fetched_at': domain!.fetchedAt,
          },
      };
}

class ReportPeriod {
  final String start;
  final String end;

  const ReportPeriod(this.start, this.end);

  static ReportPeriod? fromJson(dynamic j) {
    if (j is! Map) return null;
    return ReportPeriod('${j['start'] ?? ''}', '${j['end'] ?? ''}');
  }

  Map<String, dynamic> toJson() => {'start': start, 'end': end};
}

class ReportSummary {
  final String slug;
  final String project;
  final String title;
  final String description;
  final ReportPeriod? period;
  final int datasetCount;
  final String updatedAt;
  final List<String> tags;
  final String dataTier;
  final String visibility;

  /// False for a placeholder report that this viewer cannot open.
  final bool canView;

  const ReportSummary({
    required this.slug,
    required this.project,
    required this.title,
    required this.description,
    required this.period,
    required this.datasetCount,
    required this.updatedAt,
    required this.tags,
    this.dataTier = 'sample',
    this.visibility = 'public',
    this.canView = true,
  });

  factory ReportSummary.fromJson(Map<String, dynamic> j) => ReportSummary(
        slug: j['slug'] as String,
        project: (j['project'] ?? '') as String,
        title: (j['title'] ?? j['slug']) as String,
        description: (j['description'] ?? '') as String,
        period: ReportPeriod.fromJson(j['period']),
        datasetCount: (j['dataset_count'] as num?)?.toInt() ?? 0,
        updatedAt: (j['updated_at'] ?? '') as String,
        tags: ((j['tags'] as List?) ?? const []).map((e) => '$e').toList(),
        dataTier: (j['data_tier'] ?? 'sample') as String,
        visibility: (j['visibility'] ?? 'public') as String,
        canView: (j['can_view'] as bool?) ?? true,
      );

  Map<String, dynamic> toJson() => {
        'slug': slug,
        'project': project,
        'title': title,
        'description': description,
        'period': period?.toJson(),
        'dataset_count': datasetCount,
        'updated_at': updatedAt,
        'tags': tags,
        'data_tier': dataTier,
        'visibility': visibility,
        'can_view': canView,
      };
}

/// One page of a catalog list.
class Paged<T> {
  final List<T> items;
  final int page;
  final int pageSize;
  final int total;

  const Paged({required this.items, required this.page, required this.pageSize, required this.total});

  int get pages => total == 0 ? 1 : ((total + pageSize - 1) ~/ pageSize);

  static Paged<T> fromJson<T>(Map<String, dynamic> j, T Function(Map<String, dynamic>) item) => Paged<T>(
        items: ((j['items'] as List?) ?? const []).map((e) => item(e as Map<String, dynamic>)).toList(),
        page: (j['page'] as num?)?.toInt() ?? 1,
        pageSize: (j['page_size'] as num?)?.toInt() ?? 12,
        total: (j['total'] as num?)?.toInt() ?? 0,
      );
}

/// One value per report (API stats: rows or charts of a report).
class ReportCount {
  final String report;
  final String title;
  final int value;

  const ReportCount(this.report, this.title, this.value);

  factory ReportCount.fromJson(Map<String, dynamic> j) => ReportCount('${j['report']}', '${j['title'] ?? j['report']}', (j['value'] as num?)?.toInt() ?? 0);
}

/// Rows of one day (API stats).
class DayCount {
  final String date;
  final int rows;

  const DayCount(this.date, this.rows);

  factory DayCount.fromJson(Map<String, dynamic> j) => DayCount('${j['date']}', (j['rows'] as num?)?.toInt() ?? 0);
}

/// Numbers of one project (API: /api/v1/projects/{project}/stats, and items of /api/v1/stats).
class ProjectStats {
  final String project;
  final int reports;
  final int charts;
  final int rows;
  final int bytes;
  final String? periodStart;
  final String? periodEnd;
  final List<ReportCount> rowsByReport;
  final List<ReportCount> chartsByReport;
  final List<DayCount> rowsByDay;

  const ProjectStats({
    required this.project,
    this.reports = 0,
    this.charts = 0,
    this.rows = 0,
    this.bytes = 0,
    this.periodStart,
    this.periodEnd,
    this.rowsByReport = const [],
    this.chartsByReport = const [],
    this.rowsByDay = const [],
  });

  static int _int(dynamic v) => (v as num?)?.toInt() ?? 0;

  static List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
      v is List ? [for (final e in v) if (e is Map) f(Map<String, dynamic>.from(e))] : <T>[];

  factory ProjectStats.fromJson(Map<String, dynamic> j) => ProjectStats(
        project: '${j['project']}',
        reports: _int(j['reports']),
        charts: _int(j['charts']),
        rows: _int(j['rows']),
        bytes: _int(j['bytes']),
        periodStart: j['period_start'] as String?,
        periodEnd: j['period_end'] as String?,
        rowsByReport: _list(j['rows_by_report'], ReportCount.fromJson),
        chartsByReport: _list(j['charts_by_report'], ReportCount.fromJson),
        rowsByDay: _list(j['rows_by_day'], DayCount.fromJson),
      );
}

/// Totals of all projects (API: /api/v1/stats).
class GlobalStats {
  final int projects;
  final int reports;
  final int charts;
  final int rows;
  final int bytes;
  final Map<String, ProjectStats> byProject;

  const GlobalStats({this.projects = 0, this.reports = 0, this.charts = 0, this.rows = 0, this.bytes = 0, this.byProject = const {}});

  factory GlobalStats.fromJson(Map<String, dynamic> j) {
    final items = ProjectStats._list(j['items'], ProjectStats.fromJson);
    return GlobalStats(
      projects: ProjectStats._int(j['projects']),
      reports: ProjectStats._int(j['reports']),
      charts: ProjectStats._int(j['charts']),
      rows: ProjectStats._int(j['rows']),
      bytes: ProjectStats._int(j['bytes']),
      byProject: {for (final s in items) s.project: s},
    );
  }
}
