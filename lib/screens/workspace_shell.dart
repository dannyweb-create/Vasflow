import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backup_scheduler.dart';
import '../theme/brand.dart';
import '../theme/glass_widgets.dart';
import 'ai_agent_screen.dart';
import 'clients_screen.dart';
import 'dashboard_screen.dart';
import 'settings_screen.dart';

const _navItems = <_NavItem>[
  _NavItem(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    label: 'Home',
  ),
  _NavItem(
    icon: Icons.people_alt_outlined,
    selectedIcon: Icons.people_alt_rounded,
    label: 'Clients',
  ),
  _NavItem(
    icon: Icons.smart_toy_outlined,
    selectedIcon: Icons.smart_toy_rounded,
    label: 'AI',
  ),
  _NavItem(
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
    label: 'Profile',
  ),
];

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// Hosts the four bottom tabs: Home, Clients, AI and Profile.
/// An IndexedStack keeps each tab alive, so positions and loaded data are
/// preserved when moving between tabs.
class WorkspaceShell extends StatefulWidget {
  final AuthService auth;
  const WorkspaceShell({super.key, required this.auth});

  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _WorkspaceShellState extends State<WorkspaceShell> {
  int _tab = 0;
  late final tabNotifier = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    // App-open automatic backups. The scheduler dedupes per period from the
    // server-side history, so being fired on every shell mount is safe.
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      BackupScheduler.schedulerInstance.runIfDue(widget.auth);
    });
  }

  void selectTab(int index) {
    if (!mounted) return;
    setState(() => _tab = index);
    tabNotifier.value = index;
  }

  @override
  void dispose() {
    tabNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _tab,
        children: [
          DashboardScreen(
            auth: widget.auth,
            tabNotifier: tabNotifier,
            onSelectTab: selectTab,
          ),
          ClientsScreen(
            auth: widget.auth,
            fabBottomInset: AppLayout.navBarClearance,
          ),
          const AiAgentScreen(),
          SettingsScreen(auth: widget.auth),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 6, 16, AppLayout.navBarMargin),
        child: _FloatingNavBar(selectedIndex: _tab, onSelected: selectTab),
      ),
    );
  }
}

class _FloatingNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _FloatingNavBar({
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final glass = isGlass(context);
    final radius = BorderRadius.circular(AppRadii.nav);
    final borderColor =
        dark
            ? Brand.darkGlassBorder
            : glass
            ? Colors.white.withValues(alpha: 0.85)
            : scheme.outlineVariant;
    final shadows =
        dark
            ? AppShadows.glass
            : <BoxShadow>[
              BoxShadow(
                color: Brand.deepGreen.withValues(alpha: glass ? 0.18 : 0.10),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ];

    final surface = Container(
      height: AppLayout.navBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color:
            dark
                ? const Color(0xD90D241A)
                : glass
                ? Colors.white.withValues(alpha: 0.62)
                : scheme.surfaceContainerHigh.withValues(alpha: 0.96),
        borderRadius: radius,
        border: Border.all(color: borderColor),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            for (var i = 0; i < _navItems.length; i++)
              Expanded(
                child: _NavButton(
                  item: _navItems[i],
                  selected: i == selectedIndex,
                  onTap: () => onSelected(i),
                ),
              ),
          ],
        ),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: shadows),
      child:
          dark || glass
              ? ClipRRect(
                borderRadius: radius,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: surface,
                ),
              )
              : surface,
    );
  }
}

class _NavButton extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.68);
    final iconColor = selected ? scheme.onPrimary : muted;
    return Tooltip(
      message: item.label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        selected: selected,
        label: item.label,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? scheme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: selected ? AppShadows.glow : null,
                  ),
                  child: Icon(
                    selected ? item.selectedIcon : item.icon,
                    size: 22,
                    color: iconColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? scheme.primary : muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
