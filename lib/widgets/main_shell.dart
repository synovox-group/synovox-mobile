import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  static const _tabs = [
    (path: '/dashboard',    icon: Icons.grid_view_rounded,       label: 'Accueil'),
    (path: '/calls',        icon: Icons.phone_outlined,          label: 'Appels'),
    (path: '/contacts',     icon: Icons.people_outline_rounded,  label: 'Contacts'),
    (path: '/appointments', icon: Icons.calendar_today_outlined, label: 'RDV'),
    (path: '/settings',     icon: Icons.settings_outlined,       label: 'Réglages'),
  ];

  int _currentIndex(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    for (var i = 0; i < _tabs.length; i++) {
      if (loc.startsWith(_tabs[i].path)) return i;
    }
    // Map /assistants to settings tab
    if (loc.startsWith('/assistants')) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final idx = _currentIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => context.go(_tabs[i].path),
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFEFF6FF),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        destinations: _tabs
            .map((t) => NavigationDestination(
                  icon: Icon(t.icon),
                  label: t.label,
                ))
            .toList(),
      ),
    );
  }
}
