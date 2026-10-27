import 'package:flutter/material.dart';
import 'package:asodya_tracking/asodya_tracking.dart';
export 'package:asodya_tracking/asodya_tracking.dart';

const reportScreens = <TrackingScreen>[
  TrackingScreen(
    name: 'overview',
    route: '/v1/home',
    label: 'Reports overview',
  ),
  TrackingScreen(
    name: 'projects',
    route: '/v1/home/projects',
    label: 'Public projects',
  ),
  TrackingScreen(
    name: 'science',
    route: '/v1/home/science',
    label: 'Science topics',
  ),
  TrackingScreen(
    name: 'science',
    route: '/v1/home/science/:topic',
    label: 'Science topic',
  ),
  TrackingScreen(
    name: 'architecture',
    route: '/v1/home/architecture',
    label: 'Architecture',
  ),
  TrackingScreen(
    name: 'contact',
    route: '/v1/home/contact',
    label: 'Community contacts',
  ),
  TrackingScreen(name: 'catalog', route: '/v1/menu', label: 'Projects catalog'),
  TrackingScreen(
    name: 'report_catalog',
    route: '/v1/menu/:project',
    label: 'Project reports',
  ),
  TrackingScreen(
    name: 'report',
    route: '/v1/menu/:project/:report',
    label: 'Report board',
  ),
  TrackingScreen(
    name: 'dataset',
    route: '/v1/menu/:project/:report/:dataset',
    label: 'Dataset',
  ),
  TrackingScreen(
    name: 'embed',
    route: '/v1/embed/:project/:report/:dataset',
    label: 'Embedded dataset',
  ),
  TrackingScreen(name: 'sync', route: '/sync', label: 'Authentication return'),
];
const reportElements = <String, TrackingElement>{
  'auth.message.home': TrackingElement(
    id: 'auth.message.home',
    label: 'Auth message home',
    path: 'auth > message > home',
  ),
  'auth.message.action': TrackingElement(
    id: 'auth.message.action',
    label: 'Auth message action',
    path: 'auth > message > action',
  ),
  'catalog.project_mode.select': TrackingElement(
    id: 'catalog.project_mode.select',
    label: 'Catalog project mode select',
    path: 'catalog > project_mode > select',
  ),
  'public.contact.community': TrackingElement(
    id: 'public.contact.community',
    label: 'Public contact community',
    path: 'public > contact > community',
  ),
  'public.overview.login': TrackingElement(
    id: 'public.overview.login',
    label: 'Public overview login',
    path: 'public > overview > login',
  ),
  'public.overview.reports': TrackingElement(
    id: 'public.overview.reports',
    label: 'Public overview reports',
    path: 'public > overview > reports',
  ),
  'public.project.repository': TrackingElement(
    id: 'public.project.repository',
    label: 'Public project repository',
    path: 'public > project > repository',
  ),
  'public.project.website': TrackingElement(
    id: 'public.project.website',
    label: 'Public project website',
    path: 'public > project > website',
  ),
  'public.project.reports': TrackingElement(
    id: 'public.project.reports',
    label: 'Public project reports',
    path: 'public > project > reports',
  ),
  'public.science.topic': TrackingElement(
    id: 'public.science.topic',
    label: 'Public science topic',
    path: 'public > science > topic',
  ),
  'catalog.report.search': TrackingElement(
    id: 'catalog.report.search',
    label: 'Catalog report search',
    path: 'catalog > report > search',
  ),
  'catalog.session.login': TrackingElement(
    id: 'catalog.session.login',
    label: 'Catalog session login',
    path: 'catalog > session > login',
  ),
  'catalog.error.retry': TrackingElement(
    id: 'catalog.error.retry',
    label: 'Catalog error retry',
    path: 'catalog > error > retry',
  ),
  'catalog.card.open': TrackingElement(
    id: 'catalog.card.open',
    label: 'Catalog card open',
    path: 'catalog > card > open',
  ),
  'catalog.pagination.next': TrackingElement(
    id: 'catalog.pagination.next',
    label: 'Catalog pagination next',
    path: 'catalog > pagination > next',
  ),
  'catalog.pagination.previous': TrackingElement(
    id: 'catalog.pagination.previous',
    label: 'Catalog pagination previous',
    path: 'catalog > pagination > previous',
  ),
  'catalog.view.select': TrackingElement(
    id: 'catalog.view.select',
    label: 'Catalog view select',
    path: 'catalog > view > select',
  ),
  'catalog.tier.open': TrackingElement(
    id: 'catalog.tier.open',
    label: 'Catalog tier open',
    path: 'catalog > tier > open',
  ),
  'dataset.table.next': TrackingElement(
    id: 'dataset.table.next',
    label: 'Dataset table next',
    path: 'dataset > table > next',
  ),
  'dataset.table.previous': TrackingElement(
    id: 'dataset.table.previous',
    label: 'Dataset table previous',
    path: 'dataset > table > previous',
  ),
  'dataset.table.sort': TrackingElement(
    id: 'dataset.table.sort',
    label: 'Dataset table sort',
    path: 'dataset > table > sort',
  ),
  'catalog.carousel.project': TrackingElement(
    id: 'catalog.carousel.project',
    label: 'Catalog carousel project',
    path: 'catalog > carousel > project',
  ),
  'catalog.carousel.surface': TrackingElement(
    id: 'catalog.carousel.surface',
    label: 'Catalog carousel surface',
    path: 'catalog > carousel > surface',
  ),
  'catalog.carousel.arrow': TrackingElement(
    id: 'catalog.carousel.arrow',
    label: 'Catalog carousel arrow',
    path: 'catalog > carousel > arrow',
  ),
  'catalog.project.website': TrackingElement(
    id: 'catalog.project.website',
    label: 'Catalog project website',
    path: 'catalog > project > website',
  ),
  'catalog.project.reports': TrackingElement(
    id: 'catalog.project.reports',
    label: 'Catalog project reports',
    path: 'catalog > project > reports',
  ),
  'public.formula.open': TrackingElement(
    id: 'public.formula.open',
    label: 'Public formula open',
    path: 'public > formula > open',
  ),
  'public.card.open': TrackingElement(
    id: 'public.card.open',
    label: 'Public card open',
    path: 'public > card > open',
  ),
  'public.link.open': TrackingElement(
    id: 'public.link.open',
    label: 'Public link open',
    path: 'public > link > open',
  ),
  'public.feature.open': TrackingElement(
    id: 'public.feature.open',
    label: 'Public feature open',
    path: 'public > feature > open',
  ),
  'public.footer.open': TrackingElement(
    id: 'public.footer.open',
    label: 'Public footer open',
    path: 'public > footer > open',
  ),
  'report.export.format': TrackingElement(
    id: 'report.export.format',
    label: 'Report export format',
    path: 'report > export > format',
  ),
  'report.export.open': TrackingElement(
    id: 'report.export.open',
    label: 'Report export open',
    path: 'report > export > open',
  ),
  'report.layout.resize': TrackingElement(
    id: 'report.layout.resize',
    label: 'Report layout resize',
    path: 'report > layout > resize',
  ),
  'report.layout.drag': TrackingElement(
    id: 'report.layout.drag',
    label: 'Report layout drag',
    path: 'report > layout > drag',
  ),
  'dataset.filter.range.input': TrackingElement(
    id: 'dataset.filter.range.input',
    label: 'Dataset filter range input',
    path: 'dataset > filter > range > input',
  ),
  'dataset.filter.category.apply': TrackingElement(
    id: 'dataset.filter.category.apply',
    label: 'Dataset filter category apply',
    path: 'dataset > filter > category > apply',
  ),
  'dataset.filter.category.all': TrackingElement(
    id: 'dataset.filter.category.all',
    label: 'Dataset filter category all',
    path: 'dataset > filter > category > all',
  ),
  'dataset.filter.category.toggle': TrackingElement(
    id: 'dataset.filter.category.toggle',
    label: 'Dataset filter category toggle',
    path: 'dataset > filter > category > toggle',
  ),
  'dataset.filter.category.search': TrackingElement(
    id: 'dataset.filter.category.search',
    label: 'Dataset filter category search',
    path: 'dataset > filter > category > search',
  ),
  'dataset.filter.category.open': TrackingElement(
    id: 'dataset.filter.category.open',
    label: 'Dataset filter category open',
    path: 'dataset > filter > category > open',
  ),
  'dataset.filter.category.option': TrackingElement(
    id: 'dataset.filter.category.option',
    label: 'Dataset filter category option',
    path: 'dataset > filter > category > option',
  ),
  'dataset.filter.reset': TrackingElement(
    id: 'dataset.filter.reset',
    label: 'Dataset filter reset',
    path: 'dataset > filter > reset',
  ),
  'dataset.menu.open': TrackingElement(
    id: 'dataset.menu.open',
    label: 'Dataset menu open',
    path: 'dataset > menu > open',
  ),
  'dataset.info.close': TrackingElement(
    id: 'dataset.info.close',
    label: 'Dataset info close',
    path: 'dataset > info > close',
  ),
  'dataset.error.retry': TrackingElement(
    id: 'dataset.error.retry',
    label: 'Dataset error retry',
    path: 'dataset > error > retry',
  ),
  'dataset.view.expand': TrackingElement(
    id: 'dataset.view.expand',
    label: 'Dataset view expand',
    path: 'dataset > view > expand',
  ),
  'report.layout.edit': TrackingElement(
    id: 'report.layout.edit',
    label: 'Report layout edit',
    path: 'report > layout > edit',
  ),
  'report.layout.save': TrackingElement(
    id: 'report.layout.save',
    label: 'Report layout save',
    path: 'report > layout > save',
  ),
  'report.layout.cancel': TrackingElement(
    id: 'report.layout.cancel',
    label: 'Report layout cancel',
    path: 'report > layout > cancel',
  ),
  'report.layout.reset': TrackingElement(
    id: 'report.layout.reset',
    label: 'Report layout reset',
    path: 'report > layout > reset',
  ),
  'report.section.cancel': TrackingElement(
    id: 'report.section.cancel',
    label: 'Report section cancel',
    path: 'report > section > cancel',
  ),
  'report.section.save': TrackingElement(
    id: 'report.section.save',
    label: 'Report section save',
    path: 'report > section > save',
  ),
  'report.section.name': TrackingElement(
    id: 'report.section.name',
    label: 'Report section name',
    path: 'report > section > name',
  ),
  'report.section.rename': TrackingElement(
    id: 'report.section.rename',
    label: 'Report section rename',
    path: 'report > section > rename',
  ),
  'report.section.select': TrackingElement(
    id: 'report.section.select',
    label: 'Report section select',
    path: 'report > section > select',
  ),
  'dataset.share.copy': TrackingElement(
    id: 'dataset.share.copy',
    label: 'Dataset share copy',
    path: 'dataset > share > copy',
  ),
  'dataset.share.close': TrackingElement(
    id: 'dataset.share.close',
    label: 'Dataset share close',
    path: 'dataset > share > close',
  ),
  'dataset.share.mode': TrackingElement(
    id: 'dataset.share.mode',
    label: 'Dataset share mode',
    path: 'dataset > share > mode',
  ),
  'shell.breadcrumb.open': TrackingElement(
    id: 'shell.breadcrumb.open',
    label: 'Shell breadcrumb open',
    path: 'shell > breadcrumb > open',
  ),
  'shell.guest.dismiss': TrackingElement(
    id: 'shell.guest.dismiss',
    label: 'Shell guest dismiss',
    path: 'shell > guest > dismiss',
  ),
  'shell.guest.signup': TrackingElement(
    id: 'shell.guest.signup',
    label: 'Shell guest signup',
    path: 'shell > guest > signup',
  ),
  'shell.guest.login': TrackingElement(
    id: 'shell.guest.login',
    label: 'Shell guest login',
    path: 'shell > guest > login',
  ),
  'report.description.expand': TrackingElement(
    id: 'report.description.expand',
    label: 'Report description expand',
    path: 'report > description > expand',
  ),
  'shell.sidebar.icon': TrackingElement(
    id: 'shell.sidebar.icon',
    label: 'Shell sidebar icon',
    path: 'shell > sidebar > icon',
  ),
  'shell.sidebar.navigate': TrackingElement(
    id: 'shell.sidebar.navigate',
    label: 'Shell sidebar navigate',
    path: 'shell > sidebar > navigate',
  ),
  'shell.sidebar.group': TrackingElement(
    id: 'shell.sidebar.group',
    label: 'Shell sidebar group',
    path: 'shell > sidebar > group',
  ),
  'shell.sidebar.toggle': TrackingElement(
    id: 'shell.sidebar.toggle',
    label: 'Shell sidebar toggle',
    path: 'shell > sidebar > toggle',
  ),
  'shell.account.logout': TrackingElement(
    id: 'shell.account.logout',
    label: 'Shell account logout',
    path: 'shell > account > logout',
  ),
  'dataset.menu.move': TrackingElement(
    id: 'dataset.menu.move',
    label: 'Dataset menu move',
    path: 'dataset > menu > move',
  ),
  'dataset.menu.minimize': TrackingElement(
    id: 'dataset.menu.minimize',
    label: 'Dataset menu minimize',
    path: 'dataset > menu > minimize',
  ),
  'dataset.menu.share': TrackingElement(
    id: 'dataset.menu.share',
    label: 'Dataset menu share',
    path: 'dataset > menu > share',
  ),
  'dataset.menu.table': TrackingElement(
    id: 'dataset.menu.table',
    label: 'Dataset menu table',
    path: 'dataset > menu > table',
  ),
  'dataset.menu.info': TrackingElement(
    id: 'dataset.menu.info',
    label: 'Dataset menu info',
    path: 'dataset > menu > info',
  ),
  'dataset.chart.surface': TrackingElement(
    id: 'dataset.chart.surface',
    label: 'Dataset chart surface',
    path: 'dataset > chart > surface',
  ),
  'shell.navigation.home': TrackingElement(
    id: 'shell.navigation.home',
    label: 'Shell navigation home',
    path: 'shell > navigation > home',
  ),
  'shell.navigation.overview': TrackingElement(
    id: 'shell.navigation.overview',
    label: 'Shell navigation overview',
    path: 'shell > navigation > overview',
  ),
  'shell.navigation.projects': TrackingElement(
    id: 'shell.navigation.projects',
    label: 'Shell navigation projects',
    path: 'shell > navigation > projects',
  ),
  'shell.navigation.reports': TrackingElement(
    id: 'shell.navigation.reports',
    label: 'Shell navigation reports',
    path: 'shell > navigation > reports',
  ),
  'shell.navigation.science': TrackingElement(
    id: 'shell.navigation.science',
    label: 'Shell navigation science',
    path: 'shell > navigation > science',
  ),
  'shell.navigation.architecture': TrackingElement(
    id: 'shell.navigation.architecture',
    label: 'Shell navigation architecture',
    path: 'shell > navigation > architecture',
  ),
  'shell.navigation.contact': TrackingElement(
    id: 'shell.navigation.contact',
    label: 'Shell navigation contact',
    path: 'shell > navigation > contact',
  ),
  'shell.navigation.menu': TrackingElement(
    id: 'shell.navigation.menu',
    label: 'Shell navigation menu',
    path: 'shell > navigation > menu',
  ),
  'shell.navigation.close': TrackingElement(
    id: 'shell.navigation.close',
    label: 'Shell navigation close',
    path: 'shell > navigation > close',
  ),
  'shell.theme.toggle': TrackingElement(
    id: 'shell.theme.toggle',
    label: 'Shell theme toggle',
    path: 'shell > theme > toggle',
  ),
  'shell.language.english': TrackingElement(
    id: 'shell.language.english',
    label: 'Shell language english',
    path: 'shell > language > english',
  ),
  'shell.language.portuguese': TrackingElement(
    id: 'shell.language.portuguese',
    label: 'Shell language portuguese',
    path: 'shell > language > portuguese',
  ),
  'shell.language.thai': TrackingElement(
    id: 'shell.language.thai',
    label: 'Shell language thai',
    path: 'shell > language > thai',
  ),
  'dataset.share.link': TrackingElement(
    id: 'dataset.share.link',
    label: 'Dataset share link',
    path: 'dataset > share > link',
  ),
  'dataset.share.embed': TrackingElement(
    id: 'dataset.share.embed',
    label: 'Dataset share embed',
    path: 'dataset > share > embed',
  ),
  'report.export.pdf': TrackingElement(
    id: 'report.export.pdf',
    label: 'Report export pdf',
    path: 'report > export > pdf',
  ),
  'report.export.markdown': TrackingElement(
    id: 'report.export.markdown',
    label: 'Report export markdown',
    path: 'report > export > markdown',
  ),
  'report.export.csv': TrackingElement(
    id: 'report.export.csv',
    label: 'Report export csv',
    path: 'report > export > csv',
  ),
  'catalog.carousel.previous': TrackingElement(
    id: 'catalog.carousel.previous',
    label: 'Catalog carousel previous',
    path: 'catalog > carousel > previous',
  ),
  'catalog.carousel.next': TrackingElement(
    id: 'catalog.carousel.next',
    label: 'Catalog carousel next',
    path: 'catalog > carousel > next',
  ),
  'catalog.tier.option': TrackingElement(
    id: 'catalog.tier.option',
    label: 'Catalog tier option',
    path: 'catalog > tier > option',
  ),
  'architecture.surface': TrackingElement(
    id: 'architecture.surface',
    label: 'Architecture surface',
    path: 'architecture > surface',
  ),
  'catalog.surface': TrackingElement(
    id: 'catalog.surface',
    label: 'Catalog surface',
    path: 'catalog > surface',
  ),
  'contact.surface': TrackingElement(
    id: 'contact.surface',
    label: 'Contact surface',
    path: 'contact > surface',
  ),
  'dataset.surface': TrackingElement(
    id: 'dataset.surface',
    label: 'Dataset surface',
    path: 'dataset > surface',
  ),
  'embed.surface': TrackingElement(
    id: 'embed.surface',
    label: 'Embed surface',
    path: 'embed > surface',
  ),
  'overview.surface': TrackingElement(
    id: 'overview.surface',
    label: 'Overview surface',
    path: 'overview > surface',
  ),
  'projects.surface': TrackingElement(
    id: 'projects.surface',
    label: 'Projects surface',
    path: 'projects > surface',
  ),
  'report.surface': TrackingElement(
    id: 'report.surface',
    label: 'Report surface',
    path: 'report > surface',
  ),
  'report_catalog.surface': TrackingElement(
    id: 'report_catalog.surface',
    label: 'Report catalog surface',
    path: 'report_catalog > surface',
  ),
  'science.surface': TrackingElement(
    id: 'science.surface',
    label: 'Science surface',
    path: 'science > surface',
  ),
  'sync.surface': TrackingElement(
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
    TrackingScope.maybeOf(context)?.event('submit', reportElements[id]!);
void trackInput(
  BuildContext context,
  String id,
  String? value, {
  bool sensitive = false,
}) => TrackingScope.maybeOf(
  context,
)?.event('input', reportElements[id]!, value: value, sensitive: sensitive);
