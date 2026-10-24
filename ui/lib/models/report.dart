import 'catalog.dart';

/// Report contract models (API: /projects/{project}/reports/{report}, .../datasets/{id}
/// and the guest showcase /projects/{project}/showcase/{report}).
/// The API sends data and data descriptions only; the frontend decides layout and charts.
class FieldInfo {
  final String name;
  final String label;

  /// string, integer, float, percent, date, datetime, hour, latitude, longitude
  final String type;

  /// dimension or measure
  final String role;
  final String? unit;
  final int? decimals;

  const FieldInfo({required this.name, required this.label, required this.type, required this.role, this.unit, this.decimals});

  bool get isDimension => role == 'dimension';
  bool get isNumeric => const {'integer', 'float', 'percent', 'hour', 'latitude', 'longitude'}.contains(type);
  bool get isTime => const {'date', 'datetime', 'hour'}.contains(type);

  factory FieldInfo.fromJson(Map<String, dynamic> j) => FieldInfo(
        name: j['name'] as String,
        label: (j['label'] ?? j['name']) as String,
        type: (j['type'] ?? 'string') as String,
        role: (j['role'] ?? 'measure') as String,
        unit: j['unit'] as String?,
        decimals: (j['decimals'] as num?)?.toInt(),
      );
}

class FilterOption {
  final dynamic value;
  final String label;

  const FilterOption(this.value, this.label);

  factory FilterOption.fromJson(Map<String, dynamic> j) => FilterOption(j['value'], '${j['label'] ?? j['value']}');
}

class FilterInfo {
  final String field;
  final String label;

  /// category, date, hour or number
  final String type;
  final List<FilterOption> options;
  final dynamic min;
  final dynamic max;

  const FilterInfo({required this.field, required this.label, required this.type, this.options = const [], this.min, this.max});

  factory FilterInfo.fromJson(Map<String, dynamic> j) => FilterInfo(
        field: j['field'] as String,
        label: (j['label'] ?? j['field']) as String,
        type: (j['type'] ?? 'category') as String,
        options: ((j['options'] as List?) ?? const []).map((e) => FilterOption.fromJson(e as Map<String, dynamic>)).toList(),
        min: j['min'],
        max: j['max'],
      );
}

class DatasetDescriptor {
  final String datasetId;
  final String title;
  final String description;
  final String? equation;
  final List<FieldInfo> fields;
  final List<FilterInfo> filters;
  final String dataTier;
  final bool canView;
  final String visibility;

  const DatasetDescriptor({
    required this.datasetId,
    required this.title,
    required this.description,
    required this.equation,
    required this.fields,
    required this.filters,
    this.dataTier = 'sample',
    this.canView = true,
    this.visibility = 'public',
  });

  FieldInfo? field(String name) {
    for (final f in fields) {
      if (f.name == name) return f;
    }
    return null;
  }

  factory DatasetDescriptor.fromJson(Map<String, dynamic> j) => DatasetDescriptor(
        datasetId: j['dataset_id'] as String,
        title: (j['title'] ?? j['dataset_id']) as String,
        description: (j['description'] ?? '') as String,
        equation: j['equation'] as String?,
        fields: ((j['fields'] as List?) ?? const []).map((e) => FieldInfo.fromJson(e as Map<String, dynamic>)).toList(),
        filters: ((j['filters'] as List?) ?? const []).map((e) => FilterInfo.fromJson(e as Map<String, dynamic>)).toList(),
        dataTier: (j['data_tier'] ?? 'sample') as String,
        canView: (j['can_view'] as bool?) ?? true,
        visibility: (j['visibility'] ?? 'public') as String,
      );
}

class ReportView {
  final String project;
  final String report;
  final String title;
  final String description;
  final List<String> tags;
  final ReportPeriod? period;
  final String updatedAt;
  final List<DatasetDescriptor> datasets;
  final String dataTier;
  final String visibility;

  const ReportView({
    required this.project,
    required this.report,
    required this.title,
    required this.description,
    required this.tags,
    required this.period,
    required this.updatedAt,
    required this.datasets,
    this.dataTier = 'sample',
    this.visibility = 'public',
  });

  DatasetDescriptor? dataset(String id) {
    for (final d in datasets) {
      if (d.datasetId == id) return d;
    }
    return null;
  }

  factory ReportView.fromJson(Map<String, dynamic> j) => ReportView(
        project: j['project'] as String,
        report: j['report'] as String,
        title: (j['title'] ?? j['report']) as String,
        description: (j['description'] ?? '') as String,
        tags: ((j['tags'] as List?) ?? const []).map((e) => '$e').toList(),
        period: ReportPeriod.fromJson(j['period']),
        updatedAt: (j['updated_at'] ?? '') as String,
        datasets: ((j['datasets'] as List?) ?? const []).map((e) => DatasetDescriptor.fromJson(e as Map<String, dynamic>)).toList(),
        dataTier: (j['data_tier'] ?? 'sample') as String,
        visibility: (j['visibility'] ?? 'public') as String,
      );
}

/// Where a result comes from (API `lineage`).
class Lineage {
  final String calculationId;
  final int calculationVersion;
  final String calculatedAt;

  const Lineage({this.calculationId = '', this.calculationVersion = 0, this.calculatedAt = ''});

  static Lineage? fromJson(dynamic j) => j is Map
      ? Lineage(
          calculationId: '${j['calculation_id'] ?? ''}',
          calculationVersion: (j['calculation_version'] as num?)?.toInt() ?? 0,
          calculatedAt: '${j['calculated_at'] ?? ''}',
        )
      : null;
}

class DatasetPage {
  final DatasetDescriptor descriptor;
  final List<Map<String, dynamic>> rows;
  final int offset;
  final int limit;
  final int totalRows;
  final Lineage? lineage;

  const DatasetPage({required this.descriptor, required this.rows, required this.offset, required this.limit, required this.totalRows, this.lineage});

  factory DatasetPage.fromJson(Map<String, dynamic> j) => DatasetPage(
        descriptor: DatasetDescriptor.fromJson(j),
        rows: ((j['rows'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        offset: (j['offset'] as num?)?.toInt() ?? 0,
        limit: (j['limit'] as num?)?.toInt() ?? 0,
        totalRows: (j['total_rows'] as num?)?.toInt() ?? 0,
        lineage: Lineage.fromJson(j['lineage']),
      );
}

/// The guest view of a report (`GET /projects/{p}/showcase/{r}`): the report, and the
/// first page of every public card, so the guest page needs no second call per card.
class Showcase {
  final ReportView view;
  final Map<String, DatasetPage> pages;

  const Showcase(this.view, this.pages);

  factory Showcase.fromJson(Map<String, dynamic> j) {
    final descriptors = <DatasetDescriptor>[];
    final pages = <String, DatasetPage>{};
    for (final c in (j['cards'] as List? ?? const [])) {
      final card = Map<String, dynamic>.from(c as Map);
      final id = '${card['dataset_id']}';
      final d = card['descriptor'];
      final descriptor = d is Map
          ? DatasetDescriptor.fromJson({...Map<String, dynamic>.from(d), 'visibility': card['visibility'], 'can_view': true})
          : DatasetDescriptor(
              datasetId: id,
              title: '${card['title'] ?? id}',
              description: '',
              equation: null,
              fields: const [],
              filters: const [],
              dataTier: '${card['data_tier'] ?? 'sample'}',
              canView: false,
              visibility: '${card['visibility'] ?? 'restricted'}',
            );
      descriptors.add(descriptor);
      final rows = card['rows'];
      if (rows is List) {
        pages[id] = DatasetPage(
          descriptor: descriptor,
          rows: rows.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
          offset: 0,
          limit: rows.length,
          totalRows: (card['total_rows'] as num?)?.toInt() ?? rows.length,
        );
      }
    }
    final view = ReportView(
      project: '${j['project']}',
      report: '${j['report']}',
      title: '${j['title'] ?? j['report']}',
      description: '${j['description'] ?? ''}',
      tags: ((j['tags'] as List?) ?? const []).map((e) => '$e').toList(),
      period: ReportPeriod.fromJson(j['period']),
      updatedAt: '${j['updated_at'] ?? ''}',
      datasets: descriptors,
      dataTier: '${j['data_tier'] ?? 'sample'}',
      visibility: '${j['visibility'] ?? 'public'}',
    );
    return Showcase(view, pages);
  }
}
