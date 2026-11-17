import 'package:flutter/material.dart';
import 'package:screen_trail/screen_trail.dart';
export 'package:screen_trail/screen_trail.dart';

const reportScreens = <TrailScreen>[
  TrailScreen(name: 'overview', route: '/v1/home', label: 'Reports overview'),
  TrailScreen(
    name: 'projects',
    route: '/v1/home/projects',
    label: 'Public projects',
  ),
  TrailScreen(
    name: 'science',
    route: '/v1/home/science',
    label: 'Science topics',
  ),
  TrailScreen(
    name: 'science',
    route: '/v1/home/science/:topic',
    label: 'Science topic',
  ),
  TrailScreen(
    name: 'architecture',
    route: '/v1/home/architecture',
    label: 'Architecture',
  ),
  TrailScreen(
    name: 'contact',
    route: '/v1/home/contact',
    label: 'Community contacts',
  ),
  TrailScreen(name: 'catalog', route: '/v1/menu', label: 'Projects catalog'),
  TrailScreen(
    name: 'report_catalog',
    route: '/v1/menu/:project',
    label: 'Project reports',
  ),
  TrailScreen(
    name: 'report',
    route: '/v1/menu/:project/:report',
    label: 'Report board',
  ),
  TrailScreen(
    name: 'dataset',
    route: '/v1/menu/:project/:report/:dataset',
    label: 'Dataset',
  ),
  TrailScreen(
    name: 'embed',
    route: '/v1/embed/:project/:report/:dataset',
    label: 'Embedded dataset',
  ),
  TrailScreen(name: 'sync', route: '/sync', label: 'Authentication return'),
];
const reportElements = <String, TrailElement>{
  'auth.message.home': TrailElement(
    id: 'auth.message.home',
    label: 'Auth message home',
    path: 'auth > message > home',
  ),
  'auth.message.action': TrailElement(
    id: 'auth.message.action',
    label: 'Auth message action',
    path: 'auth > message > action',
  ),
  'catalog.project_mode.select': TrailElement(
    id: 'catalog.project_mode.select',
    label: 'Catalog project mode select',
    path: 'catalog > project_mode > select',
  ),
  'public.contact.community': TrailElement(
    id: 'public.contact.community',
    label: 'Public contact community',
    path: 'public > contact > community',
  ),
  'public.overview.login': TrailElement(
    id: 'public.overview.login',
    label: 'Public overview login',
    path: 'public > overview > login',
  ),
  'public.overview.reports': TrailElement(
    id: 'public.overview.reports',
    label: 'Public overview reports',
    path: 'public > overview > reports',
  ),
  'public.project.repository': TrailElement(
    id: 'public.project.repository',
    label: 'Public project repository',
    path: 'public > project > repository',
  ),
  'public.project.website': TrailElement(
    id: 'public.project.website',
    label: 'Public project website',
    path: 'public > project > website',
  ),
  'public.project.reports': TrailElement(
    id: 'public.project.reports',
    label: 'Public project reports',
    path: 'public > project > reports',
  ),
  'public.science.topic': TrailElement(
    id: 'public.science.topic',
    label: 'Public science topic',
    path: 'public > science > topic',
  ),
  'catalog.report.search': TrailElement(
    id: 'catalog.report.search',
    label: 'Catalog report search',
    path: 'catalog > report > search',
  ),
  'catalog.session.login': TrailElement(
    id: 'catalog.session.login',
    label: 'Catalog session login',
    path: 'catalog > session > login',
  ),
  'catalog.error.retry': TrailElement(
    id: 'catalog.error.retry',
    label: 'Catalog error retry',
    path: 'catalog > error > retry',
  ),
  'catalog.card.open': TrailElement(
    id: 'catalog.card.open',
    label: 'Catalog card open',
    path: 'catalog > card > open',
  ),
  'catalog.pagination.next': TrailElement(
    id: 'catalog.pagination.next',
    label: 'Catalog pagination next',
    path: 'catalog > pagination > next',
  ),
  'catalog.pagination.previous': TrailElement(
    id: 'catalog.pagination.previous',
    label: 'Catalog pagination previous',
    path: 'catalog > pagination > previous',
  ),
  'catalog.view.select': TrailElement(
    id: 'catalog.view.select',
    label: 'Catalog view select',
    path: 'catalog > view > select',
  ),
  'catalog.tier.open': TrailElement(
    id: 'catalog.tier.open',
    label: 'Catalog tier open',
    path: 'catalog > tier > open',
  ),
  'dataset.table.next': TrailElement(
    id: 'dataset.table.next',
    label: 'Dataset table next',
    path: 'dataset > table > next',
  ),
  'dataset.table.previous': TrailElement(
    id: 'dataset.table.previous',
    label: 'Dataset table previous',
    path: 'dataset > table > previous',
  ),
  'dataset.table.sort': TrailElement(
    id: 'dataset.table.sort',
    label: 'Dataset table sort',
    path: 'dataset > table > sort',
  ),
  'catalog.carousel.project': TrailElement(
    id: 'catalog.carousel.project',
    label: 'Catalog carousel project',
    path: 'catalog > carousel > project',
  ),
  'catalog.carousel.surface': TrailElement(
    id: 'catalog.carousel.surface',
    label: 'Catalog carousel surface',
    path: 'catalog > carousel > surface',
  ),
  'catalog.carousel.arrow': TrailElement(
    id: 'catalog.carousel.arrow',
    label: 'Catalog carousel arrow',
    path: 'catalog > carousel > arrow',
  ),
  'catalog.project.website': TrailElement(
    id: 'catalog.project.website',
    label: 'Catalog project website',
    path: 'catalog > project > website',
  ),
  'catalog.project.reports': TrailElement(
    id: 'catalog.project.reports',
    label: 'Catalog project reports',
    path: 'catalog > project > reports',
  ),
  'public.formula.open': TrailElement(
    id: 'public.formula.open',
    label: 'Public formula open',
    path: 'public > formula > open',
  ),
  'public.card.open': TrailElement(
    id: 'public.card.open',
    label: 'Public card open',
    path: 'public > card > open',
  ),
  'public.link.open': TrailElement(
    id: 'public.link.open',
    label: 'Public link open',
    path: 'public > link > open',
  ),
  'public.feature.open': TrailElement(
    id: 'public.feature.open',
    label: 'Public feature open',
    path: 'public > feature > open',
  ),
  'public.footer.open': TrailElement(
    id: 'public.footer.open',
    label: 'Public footer open',
    path: 'public > footer > open',
  ),
  'report.export.format': TrailElement(
    id: 'report.export.format',
    label: 'Report export format',
    path: 'report > export > format',
  ),
  'report.export.open': TrailElement(
    id: 'report.export.open',
    label: 'Report export open',
    path: 'report > export > open',
  ),
  'report.layout.resize': TrailElement(
    id: 'report.layout.resize',
    label: 'Report layout resize',
    path: 'report > layout > resize',
  ),
  'report.layout.drag': TrailElement(
    id: 'report.layout.drag',
    label: 'Report layout drag',
    path: 'report > layout > drag',
  ),
  'dataset.filter.range.input': TrailElement(
    id: 'dataset.filter.range.input',
    label: 'Dataset filter range input',
    path: 'dataset > filter > range > input',
  ),
  'dataset.filter.category.apply': TrailElement(
    id: 'dataset.filter.category.apply',
    label: 'Dataset filter category apply',
    path: 'dataset > filter > category > apply',
  ),
  'dataset.filter.category.all': TrailElement(
    id: 'dataset.filter.category.all',
    label: 'Dataset filter category all',
    path: 'dataset > filter > category > all',
  ),
  'dataset.filter.category.toggle': TrailElement(
    id: 'dataset.filter.category.toggle',
    label: 'Dataset filter category toggle',
    path: 'dataset > filter > category > toggle',
  ),
  'dataset.filter.category.search': TrailElement(
    id: 'dataset.filter.category.search',
    label: 'Dataset filter category search',
    path: 'dataset > filter > category > search',
  ),
  'dataset.filter.category.open': TrailElement(
    id: 'dataset.filter.category.open',
    label: 'Dataset filter category open',
    path: 'dataset > filter > category > open',
  ),
  'dataset.filter.category.option': TrailElement(
    id: 'dataset.filter.category.option',
    label: 'Dataset filter category option',
    path: 'dataset > filter > category > option',
  ),
  'dataset.filter.reset': TrailElement(
    id: 'dataset.filter.reset',
    label: 'Dataset filter reset',
    path: 'dataset > filter > reset',
  ),
  'dataset.menu.open': TrailElement(
    id: 'dataset.menu.open',
    label: 'Dataset menu open',
    path: 'dataset > menu > open',
  ),
  'dataset.info.close': TrailElement(
    id: 'dataset.info.close',
    label: 'Dataset info close',
    path: 'dataset > info > close',
  ),
  'dataset.error.retry': TrailElement(
    id: 'dataset.error.retry',
    label: 'Dataset error retry',
    path: 'dataset > error > retry',
  ),
  'dataset.view.expand': TrailElement(
    id: 'dataset.view.expand',
    label: 'Dataset view expand',
    path: 'dataset > view > expand',
  ),
  'report.layout.edit': TrailElement(
    id: 'report.layout.edit',
    label: 'Report layout edit',
    path: 'report > layout > edit',
  ),
  'report.layout.save': TrailElement(
    id: 'report.layout.save',
    label: 'Report layout save',
    path: 'report > layout > save',
  ),
  'report.layout.cancel': TrailElement(
    id: 'report.layout.cancel',
    label: 'Report layout cancel',
    path: 'report > layout > cancel',
  ),
  'report.layout.reset': TrailElement(
    id: 'report.layout.reset',
    label: 'Report layout reset',
    path: 'report > layout > reset',
  ),
  'report.section.cancel': TrailElement(
    id: 'report.section.cancel',
    label: 'Report section cancel',
    path: 'report > section > cancel',
  ),
  'report.section.save': TrailElement(
    id: 'report.section.save',
    label: 'Report section save',
    path: 'report > section > save',
  ),
  'report.section.name': TrailElement(
    id: 'report.section.name',
    label: 'Report section name',
    path: 'report > section > name',
  ),
  'report.section.rename': TrailElement(
    id: 'report.section.rename',
    label: 'Report section rename',
    path: 'report > section > rename',
  ),
  'report.section.select': TrailElement(
    id: 'report.section.select',
    label: 'Report section select',
    path: 'report > section > select',
  ),
  'dataset.share.copy': TrailElement(
    id: 'dataset.share.copy',
    label: 'Dataset share copy',
    path: 'dataset > share > copy',
  ),
  'dataset.share.close': TrailElement(
    id: 'dataset.share.close',
    label: 'Dataset share close',
    path: 'dataset > share > close',
  ),
  'dataset.share.mode': TrailElement(
    id: 'dataset.share.mode',
    label: 'Dataset share mode',
    path: 'dataset > share > mode',
  ),
  'shell.breadcrumb.open': TrailElement(
    id: 'shell.breadcrumb.open',
    label: 'Shell breadcrumb open',
    path: 'shell > breadcrumb > open',
  ),
  'shell.guest.dismiss': TrailElement(
    id: 'shell.guest.dismiss',
    label: 'Shell guest dismiss',
    path: 'shell > guest > dismiss',
  ),
  'shell.guest.signup': TrailElement(
    id: 'shell.guest.signup',
    label: 'Shell guest signup',
    path: 'shell > guest > signup',
  ),
  'shell.guest.login': TrailElement(
    id: 'shell.guest.login',
    label: 'Shell guest login',
    path: 'shell > guest > login',
  ),
  'report.description.expand': TrailElement(
    id: 'report.description.expand',
    label: 'Report description expand',
    path: 'report > description > expand',
  ),
  'shell.sidebar.icon': TrailElement(
    id: 'shell.sidebar.icon',
    label: 'Shell sidebar icon',
    path: 'shell > sidebar > icon',
  ),
  'shell.sidebar.navigate': TrailElement(
    id: 'shell.sidebar.navigate',
    label: 'Shell sidebar navigate',
    path: 'shell > sidebar > navigate',
  ),
  'shell.sidebar.group': TrailElement(
    id: 'shell.sidebar.group',
    label: 'Shell sidebar group',
    path: 'shell > sidebar > group',
  ),
  'shell.sidebar.toggle': TrailElement(
    id: 'shell.sidebar.toggle',
    label: 'Shell sidebar toggle',
    path: 'shell > sidebar > toggle',
  ),
  'shell.account.logout': TrailElement(
    id: 'shell.account.logout',
    label: 'Shell account logout',
    path: 'shell > account > logout',
  ),
  'dataset.menu.move': TrailElement(
    id: 'dataset.menu.move',
    label: 'Dataset menu move',
    path: 'dataset > menu > move',
  ),
  'dataset.menu.minimize': TrailElement(
    id: 'dataset.menu.minimize',
    label: 'Dataset menu minimize',
    path: 'dataset > menu > minimize',
  ),
  'dataset.menu.share': TrailElement(
    id: 'dataset.menu.share',
    label: 'Dataset menu share',
    path: 'dataset > menu > share',
  ),
  'dataset.menu.table': TrailElement(
    id: 'dataset.menu.table',
    label: 'Dataset menu table',
    path: 'dataset > menu > table',
  ),
  'dataset.menu.info': TrailElement(
    id: 'dataset.menu.info',
    label: 'Dataset menu info',
    path: 'dataset > menu > info',
  ),
  'dataset.chart.surface': TrailElement(
    id: 'dataset.chart.surface',
    label: 'Dataset chart surface',
    path: 'dataset > chart > surface',
  ),
  'shell.navigation.home': TrailElement(
    id: 'shell.navigation.home',
    label: 'Shell navigation home',
    path: 'shell > navigation > home',
  ),
  'shell.navigation.overview': TrailElement(
    id: 'shell.navigation.overview',
    label: 'Shell navigation overview',
    path: 'shell > navigation > overview',
  ),
  'shell.navigation.projects': TrailElement(
    id: 'shell.navigation.projects',
    label: 'Shell navigation projects',
    path: 'shell > navigation > projects',
  ),
  'shell.navigation.reports': TrailElement(
    id: 'shell.navigation.reports',
    label: 'Shell navigation reports',
    path: 'shell > navigation > reports',
  ),
  'shell.navigation.science': TrailElement(
    id: 'shell.navigation.science',
    label: 'Shell navigation science',
    path: 'shell > navigation > science',
  ),
  'shell.navigation.architecture': TrailElement(
    id: 'shell.navigation.architecture',
    label: 'Shell navigation architecture',
    path: 'shell > navigation > architecture',
  ),
  'shell.navigation.contact': TrailElement(
    id: 'shell.navigation.contact',
    label: 'Shell navigation contact',
    path: 'shell > navigation > contact',
  ),
  'shell.navigation.menu': TrailElement(
    id: 'shell.navigation.menu',
    label: 'Shell navigation menu',
    path: 'shell > navigation > menu',
  ),
  'shell.navigation.close': TrailElement(
    id: 'shell.navigation.close',
    label: 'Shell navigation close',
    path: 'shell > navigation > close',
  ),
  'shell.theme.toggle': TrailElement(
    id: 'shell.theme.toggle',
    label: 'Shell theme toggle',
    path: 'shell > theme > toggle',
  ),
  'shell.language.english': TrailElement(
    id: 'shell.language.english',
    label: 'Shell language english',
    path: 'shell > language > english',
  ),
  'shell.language.portuguese': TrailElement(
    id: 'shell.language.portuguese',
    label: 'Shell language portuguese',
    path: 'shell > language > portuguese',
  ),
  'shell.language.thai': TrailElement(
    id: 'shell.language.thai',
    label: 'Shell language thai',
    path: 'shell > language > thai',
  ),
  'dataset.share.link': TrailElement(
    id: 'dataset.share.link',
    label: 'Dataset share link',
    path: 'dataset > share > link',
  ),
  'dataset.share.embed': TrailElement(
    id: 'dataset.share.embed',
    label: 'Dataset share embed',
    path: 'dataset > share > embed',
  ),
  'report.export.pdf': TrailElement(
    id: 'report.export.pdf',
    label: 'Report export pdf',
    path: 'report > export > pdf',
  ),
  'report.export.markdown': TrailElement(
    id: 'report.export.markdown',
    label: 'Report export markdown',
    path: 'report > export > markdown',
  ),
  'report.export.csv': TrailElement(
    id: 'report.export.csv',
    label: 'Report export csv',
    path: 'report > export > csv',
  ),
  'catalog.carousel.previous': TrailElement(
    id: 'catalog.carousel.previous',
    label: 'Catalog carousel previous',
    path: 'catalog > carousel > previous',
  ),
  'catalog.carousel.next': TrailElement(
    id: 'catalog.carousel.next',
    label: 'Catalog carousel next',
    path: 'catalog > carousel > next',
  ),
  'catalog.tier.option': TrailElement(
    id: 'catalog.tier.option',
    label: 'Catalog tier option',
    path: 'catalog > tier > option',
  ),
  'architecture.surface': TrailElement(
    id: 'architecture.surface',
    label: 'Architecture surface',
    path: 'architecture > surface',
  ),
  'catalog.surface': TrailElement(
    id: 'catalog.surface',
    label: 'Catalog surface',
    path: 'catalog > surface',
  ),
  'contact.surface': TrailElement(
    id: 'contact.surface',
    label: 'Contact surface',
    path: 'contact > surface',
  ),
  'dataset.surface': TrailElement(
    id: 'dataset.surface',
    label: 'Dataset surface',
    path: 'dataset > surface',
  ),
  'embed.surface': TrailElement(
    id: 'embed.surface',
    label: 'Embed surface',
    path: 'embed > surface',
  ),
  'overview.surface': TrailElement(
    id: 'overview.surface',
    label: 'Overview surface',
    path: 'overview > surface',
  ),
  'projects.surface': TrailElement(
    id: 'projects.surface',
    label: 'Projects surface',
    path: 'projects > surface',
  ),
  'report.surface': TrailElement(
    id: 'report.surface',
    label: 'Report surface',
    path: 'report > surface',
  ),
  'report_catalog.surface': TrailElement(
    id: 'report_catalog.surface',
    label: 'Report catalog surface',
    path: 'report_catalog > surface',
  ),
  'science.surface': TrailElement(
    id: 'science.surface',
    label: 'Science surface',
    path: 'science > surface',
  ),
  'sync.surface': TrailElement(
    id: 'sync.surface',
    label: 'Sync surface',
    path: 'sync > surface',
  ),
};
Widget track(
  String id,
  Widget child, {
  TextEditingController? controller,
  bool sensitive = false,
}) => controller == null
    ? TrackedElement(element: reportElements[id]!, child: child)
    : TrackedInput(
        element: reportElements[id]!,
        controller: controller,
        sensitive: sensitive,
        child: child,
      );
void trackSubmit(BuildContext context, String id) =>
    ScreenTrailScope.maybeOf(context)?.event('submit', reportElements[id]!);
void trackInput(
  BuildContext context,
  String id,
  String? value, {
  bool sensitive = false,
}) => ScreenTrailScope.maybeOf(
  context,
)?.event('input', reportElements[id]!, value: value, sensitive: sensitive);
