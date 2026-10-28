import 'package:flutter/material.dart';
import '../services/client_repository.dart';
import '../models/client_record_extensions.dart';

class PipelineScreen extends StatefulWidget {
  final ClientRepository repo;
  const PipelineScreen({super.key, required this.repo});
  @override State<PipelineScreen> createState() => _PipelineScreenState();
}
class _PipelineScreenState extends State<PipelineScreen> {
  static const stages=['New lead','Consultation','Documents','Application submitted','Visa decision','Completed'];
  @override Widget build(BuildContext context) => Scaffold(appBar:AppBar(title:const Text('Client pipeline')), body:FutureBuilder(future:widget.repo.all(), builder:(ctx,s) {
    if(!s.hasData) return const Center(child:CircularProgressIndicator());
    final all=s.data!;
    return ListView(scrollDirection:Axis.horizontal, children:stages.map((stage) => SizedBox(width:270, child:Card(margin:const EdgeInsets.all(8), child:Column(children:[
      Padding(padding:const EdgeInsets.all(14), child:Row(children:[Expanded(child:Text(stage,style:const TextStyle(fontWeight:FontWeight.bold))),Text('${all.where((c)=>c.stage==stage).length}') ])),
      const Divider(height:1),
      Expanded(child:ListView(children:all.where((c)=>c.stage==stage).map((c)=>Card(margin:const EdgeInsets.all(8),child:ListTile(title:Text(c.fullName),subtitle:Text(c.country),trailing:PopupMenuButton<String>(onSelected:(v) async { await widget.repo.upsert(c.copyWithStage(v)); if(mounted)setState((){}); }, itemBuilder:(_)=>stages.map((v)=>PopupMenuItem(value:v,child:Text('Move to $v'))).toList())))).toList()))
    ])))).toList());
  }));
}
