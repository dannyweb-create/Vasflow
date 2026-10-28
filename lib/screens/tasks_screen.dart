import 'package:flutter/material.dart';

class TasksScreen extends StatefulWidget { const TasksScreen({super.key}); @override State<TasksScreen> createState()=>_TasksScreenState(); }
class _TasksScreenState extends State<TasksScreen> {
  final items=<String>[];
  Future<void> add() async {
    final c=TextEditingController();
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('New task'),content:TextField(controller:c,autofocus:true,decoration:const InputDecoration(labelText:'Task or reminder')),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Add'))]));
    if(ok==true && c.text.trim().isNotEmpty) setState(()=>items.add(c.text.trim()));
  }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Tasks & reminders'),actions:[IconButton(onPressed:add,icon:const Icon(Icons.add))]),body:items.isEmpty?const Center(child:Text('No tasks yet. Add a follow-up reminder.')):ListView(children:List.generate(items.length,(i)=>CheckboxListTile(value:false,onChanged:(_)=>setState(()=>items.removeAt(i)),title:Text(items[i]),secondary:const Icon(Icons.notifications_none)))));
}
