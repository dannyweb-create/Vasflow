import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatelessWidget {
  final AuthService auth; final ValueChanged<bool> onThemeChanged;
  const SettingsScreen({super.key,required this.auth,required this.onThemeChanged});
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Settings')),body:ListView(padding:const EdgeInsets.all(16),children:[
    Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.admin_panel_settings_outlined)),title:Text(auth.currentEmail.isEmpty?'Signed in':auth.currentEmail),subtitle:Text('Role: ${auth.role.toUpperCase()}'),)),
    SwitchListTile(title:const Text('Dark mode'),subtitle:const Text('Switch between light and dark appearance'),value:Theme.of(context).brightness==Brightness.dark,onChanged:onThemeChanged),
    const ListTile(leading:Icon(Icons.people_outline),title:Text('Team & invite codes'),subtitle:Text('Admin-generated temporary staff codes require a secure backend function.')),
    const ListTile(leading:Icon(Icons.security_outlined),title:Text('Security & privacy'),subtitle:Text('Production encryption, row-level security and audit policies must be enabled in Supabase.')),
    const ListTile(leading:Icon(Icons.cloud_off_outlined),title:Text('Offline mode'),subtitle:Text('Client records are cached locally. Local cache is not encrypted in this starter.')),
    const ListTile(leading:Icon(Icons.info_outline),title:Text('About VasFlow'),subtitle:Text('Visa Consultant Admin Management · Starter build')),
    const SizedBox(height:12),
    FilledButton.tonalIcon(onPressed:() async { await auth.signOut(); if(context.mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder:(_)=>LoginScreen(onThemeChanged:onThemeChanged)),(r)=>false); },icon:const Icon(Icons.logout),label:const Text('Log out')),
  ]));
}
