import 'package:flutter/material.dart';
import '../layouts/report_layout.dart';
import '../models/report.dart';
import '../services/catalog_service.dart';
import '../services/report_service.dart';
import '../themes/catalog_brands.dart';
import '../themes/theme_registry.dart';
import '../widgets/report/dataset_slot.dart';
import '../utils/browser.dart';
import 'dataset_full_view.dart';

/// The original Reports card renderer, without application navigation.
class EmbedView extends StatefulWidget {
  final String project, report, dataset, language;
  final Map<String,String> query;
  const EmbedView({super.key,required this.project,required this.report,required this.dataset,required this.language,required this.query});
  @override State<EmbedView> createState()=>_EmbedViewState();
}
class _EmbedViewState extends State<EmbedView> {
  late final service=ReportService(ReportService.instance.api,publicOnly:true);
  late final Future<ReportView> report = load();
  Future<ReportView> load() async {
    await CatalogService.instance.project(widget.project,lang:widget.language);
    return service.report(widget.project,widget.report,lang:widget.language);
  }
  @override Widget build(BuildContext context) => FutureBuilder<ReportView>(future:report,builder:(context,snapshot) {
    if(snapshot.hasError) return const Scaffold(body:Center(child:Icon(Icons.error_outline)));
    if(!snapshot.hasData) return const Scaffold(body:Center(child:CircularProgressIndicator()));
    final view=snapshot.data!;
    final visual=DatasetFullView.visualOf(widget.query['visual']);
    final slot=LayoutRegistry.sectionsFor(view).expand((s)=>s).where((s)=>s.datasetId==widget.dataset && (visual==null || s.visual==visual)).firstOrNull ?? Slot(widget.dataset,visual:visual ?? Visual.auto);
    final brightness=switch(widget.query['theme']){'light'=>Brightness.light,'dark'=>Brightness.dark,_=>Theme.of(context).brightness};
    return ListenableBuilder(listenable:CatalogBrands.instance,builder:(context,_)=>Theme(data:ThemeRegistry.theme(widget.project,brightness),child:Builder(builder:(context)=>Scaffold(body:
      widget.query['render']=='full' ? DatasetFullView(project:widget.project,report:widget.report,datasetId:widget.dataset,visual:visual,filters:DatasetFullView.filtersOf(widget.query),table:widget.query['view']=='table',language:widget.language,compact:true,service:service,onReady:markEmbedReady) :
      Padding(padding:const EdgeInsets.all(12),child:DatasetSlot(key:ValueKey('${widget.dataset}/${widget.query}'),project:widget.project,report:widget.report,view:view,slot:slot,fill:true,interactive:false,service:service,onReady:markEmbedReady,language:widget.language,initialFilters:DatasetFullView.filtersOf(widget.query),initialTable:widget.query['view']=='table'))
    ))));
  });
}
