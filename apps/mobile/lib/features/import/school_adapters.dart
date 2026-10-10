import 'haut_parser.dart';
import 'hlju_parser.dart';

class SchoolImportBundle {
  const SchoolImportBundle({
    required this.courses,
    this.extras = const [],
    this.sourceTerm = '',
    this.sourceFirstMonday,
    this.metadata = const {},
    this.warnings = const [],
  });

  final List<Map<String, dynamic>> courses;
  final List<Map<String, dynamic>> extras;
  final String sourceTerm;
  final String? sourceFirstMonday;
  final Map<String, dynamic> metadata;
  final List<String> warnings;
}

typedef SchoolImportParser = SchoolImportBundle Function(Map value);

class SchoolAdapter {
  const SchoolAdapter({
    required this.id,
    required this.name,
    required this.source,
    required this.readerAsset,
    required this.loginUrl,
    required this.origins,
    required this.courseOrigins,
    required this.httpsUpgradeHosts,
    required this.instructions,
    required this.description,
    required this.keywords,
    required this.parse,
    this.insecureLoginPaths = const [],
    this.desktopBrowser = false,
  });

  final String id, name, source, readerAsset, loginUrl;
  final String instructions, description, keywords;
  final List<String> origins, courseOrigins, httpsUpgradeHosts;
  final List<String> insecureLoginPaths;
  final SchoolImportParser parse;
  final bool desktopBrowser;

  bool matches(String query) =>
      '$name $keywords'.toLowerCase().contains(query.trim().toLowerCase());
}

SchoolImportBundle _parseHaut(Map value) => SchoolImportBundle(
  courses: parseHautCourses(value['rows'] as List),
  sourceTerm: '${value['sourceTerm'] ?? ''}',
  metadata: {'periods': hautPeriods},
);

// 河南工业大学作息，按用户提供的10节原始时间预填，不统一改成45分钟。
const hautPeriods = [
  {'section': 1, 'start': '08:30', 'end': '09:15'},
  {'section': 2, 'start': '09:20', 'end': '10:05'},
  {'section': 3, 'start': '10:25', 'end': '11:05'},
  {'section': 4, 'start': '11:10', 'end': '12:00'},
  {'section': 5, 'start': '14:30', 'end': '15:15'},
  {'section': 6, 'start': '15:20', 'end': '16:05'},
  {'section': 7, 'start': '16:25', 'end': '17:10'},
  {'section': 8, 'start': '17:15', 'end': '18:00'},
  {'section': 9, 'start': '19:30', 'end': '20:15'},
  {'section': 10, 'start': '20:20', 'end': '21:05'},
];

SchoolImportBundle _parseHlju(Map value) {
  final parsed = parseHljuImport(value);
  return SchoolImportBundle(
    courses: parsed.courses,
    extras: parsed.extras,
    sourceTerm: parsed.sourceTerm,
    sourceFirstMonday: parsed.sourceFirstMonday,
    metadata: parsed.metadata,
    warnings: parsed.warnings,
  );
}

const hautSchool = SchoolAdapter(
  id: 'haut',
  name: '河南工业大学',
  source: 'haut_webview',
  readerAsset: 'assets/haut_reader.js',
  loginUrl: 'https://jwglxt.haut.edu.cn/jwglxt/xtgl/login_slogin.html',
  origins: ['https://jwglxt.haut.edu.cn'],
  courseOrigins: ['https://jwglxt.haut.edu.cn'],
  httpsUpgradeHosts: ['jwglxt.haut.edu.cn'],
  instructions: '登录后进入“信息查询 → 个人课表查询”。',
  description: '教务课表',
  keywords: 'haut 郑州',
  parse: _parseHaut,
);

const hljuSchool = SchoolAdapter(
  id: 'hlju',
  name: '黑龙江大学',
  source: 'hlju_webview',
  readerAsset: 'assets/hlju_reader.js',
  loginUrl:
      'https://sso.hlju.edu.cn/cas/login?service=http%3A%2F%2Fxsxk.hlju.edu.cn%2Fcas',
  origins: [
    'https://sso.hlju.edu.cn',
    'https://authserver.hlju.edu.cn',
    'http://xsxk.hlju.edu.cn',
  ],
  courseOrigins: ['http://xsxk.hlju.edu.cn'],
  httpsUpgradeHosts: ['sso.hlju.edu.cn', 'authserver.hlju.edu.cn'],
  insecureLoginPaths: ['/authentication/require'],
  instructions: '登录本科教务，打开个人课表并选择要导入的学期。',
  description: '本科教务课表',
  keywords: 'hlju 黑大 哈尔滨',
  parse: _parseHlju,
  // The portal explicitly rejects every mobile UA, regardless of version.
  desktopBrowser: true,
);

const supportedSchools = [hautSchool, hljuSchool];

SchoolAdapter? schoolAdapter(String id) =>
    supportedSchools.where((school) => school.id == id).firstOrNull;
