import 'package:flutter/material.dart';

import 'chats/chats_screen.dart';
import 'home_screen.dart';
import 'settings/settings_screen.dart';
import 'shorts/shorts_screen.dart';
import 'widgets/floating_nav_bar.dart';

/// The four top-level destinations, behind a floating bottom bar.
///
/// An [IndexedStack], not a `PageView`: these are destinations rather than a
/// sequence, and swiping sideways between a feed and a video player would fight
/// the horizontal swipe the feed already uses to move between For You and
/// Following. The stack also keeps all four mounted, so a half-scrolled feed and
/// a half-watched clip are still there when you come back.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  var _index = 0;

  static const _destinations = [
    NavDestination(
      label: 'Feed',
      icon: Icons.dynamic_feed_outlined,
      selectedIcon: Icons.dynamic_feed,
    ),
    NavDestination(
      label: 'Messages',
      icon: Icons.forum_outlined,
      selectedIcon: Icons.forum,
    ),
    NavDestination(
      label: 'Shorts',
      icon: Icons.play_circle_outline,
      selectedIcon: Icons.play_circle,
    ),
    NavDestination(
      label: 'Profile',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The bar floats over the content, so the body has to run the full height
      // behind it. Each screen adds `FloatingNavBar.spaceFor` to its own bottom
      // padding rather than being inset here, or the frosted feed header would
      // lose the content it blurs.
      extendBody: true,
      body: IndexedStack(
        index: _index,
        children: const [
          HomeScreen(),
          ChatsScreen(),
          ShortsScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: FloatingNavBar(
        destinations: _destinations,
        currentIndex: _index,
        onSelected: (index) {
          if (index == _index) return;
          setState(() => _index = index);
        },
      ),
    );
  }
}
