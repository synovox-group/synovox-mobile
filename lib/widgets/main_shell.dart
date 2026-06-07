import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  static const _tabs = [
    _Tab('/dashboard',    Icons.grid_view_rounded,      Icons.grid_view_rounded,      'Accueil'),
    _Tab('/calls',        Icons.phone_rounded,           Icons.phone_outlined,          'Appels'),
    _Tab('/contacts',     Icons.people_rounded,          Icons.people_outline_rounded,  'Contacts'),
    _Tab('/appointments', Icons.calendar_month_rounded,  Icons.calendar_month_outlined, 'RDV'),
    _Tab('/settings',     Icons.settings_rounded,        Icons.settings_outlined,       'Réglages'),
  ];

  int _currentIndex(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    for (var i = 0; i < _tabs.length; i++) {
      if (loc.startsWith(_tabs[i].path)) return i;
    }
    if (loc.startsWith('/assistants')) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final idx = _currentIndex(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        body: child,
        bottomNavigationBar: _BottomNav(currentIndex: idx),
      ),
    );
  }
}

class _Tab {
  final String path;
  final IconData activeIcon;
  final IconData inactiveIcon;
  final String label;
  const _Tab(this.path, this.activeIcon, this.inactiveIcon, this.label);
}

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  const _BottomNav({required this.currentIndex});

  static const _primary  = Color(0xFF2563EB);
  static const _inactive = Color(0xFF94A3B8);
  static const _activeBg = Color(0xFFEFF6FF);
  static const _tabs     = MainShell._tabs;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: List.generate(_tabs.length, (i) {
            final active = i == currentIndex;
            final tab = _tabs[i];
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => context.go(tab.path),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: active ? _activeBg : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          active ? tab.activeIcon : tab.inactiveIcon,
                          size: 22,
                          color: active ? _primary : _inactive,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tab.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                          color: active ? _primary : _inactive,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
