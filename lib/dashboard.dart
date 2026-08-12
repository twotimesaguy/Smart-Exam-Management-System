import 'package:flutter/material.dart';
import 'package:flutter_application_1/allocation_module.dart';
import 'package:flutter_application_1/api_service.dart';
import 'package:flutter_application_1/app_notification.dart';
import 'package:flutter_application_1/att_screen.dart';
import 'package:flutter_application_1/disciplinary_officer_module.dart';
import 'package:flutter_application_1/local_auth.dart';
import 'package:flutter_application_1/malp_reporting.dart';
import 'package:flutter_application_1/my_assignment_module.dart';
import 'package:flutter_application_1/profile_module.dart';
import 'package:flutter_application_1/student_registration_module.dart';

class Dashboard extends StatelessWidget {
  const Dashboard({
    required this.currentUser,
    required this.onLogout,
    super.key,
  });

  final LocalUser currentUser;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return MainNavigation(currentUser: currentUser, onLogout: onLogout);
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({
    required this.currentUser,
    required this.onLogout,
    super.key,
  });

  final LocalUser currentUser;
  final VoidCallback onLogout;

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;
  List<AppNotification> _notifications = const [];
  bool _isLoadingNotifications = false;

  bool get _isAdmin => widget.currentUser.role == AppUserRole.admin;
  bool get _isDisciplinaryOfficer =>
      widget.currentUser.role == AppUserRole.disciplinaryOfficer;

  List<Widget> get _pages {
    if (_isAdmin) {
      return [
        const AllocationModule(),
        const StudentRegistrationModule(),
        AttendanceModule(currentUser: widget.currentUser),
        MalpReporting(currentUser: widget.currentUser),
        ProfileModule(currentUser: widget.currentUser),
      ];
    }

    if (_isDisciplinaryOfficer) {
      return [
        DisciplinaryOfficerModule(currentUser: widget.currentUser),
        ProfileModule(currentUser: widget.currentUser),
      ];
    }

    return [
      MyAssignmentModule(currentUser: widget.currentUser),
      const StudentRegistrationModule(),
      AttendanceModule(currentUser: widget.currentUser),
      MalpReporting(currentUser: widget.currentUser),
      ProfileModule(currentUser: widget.currentUser),
    ];
  }

  List<NavigationDestination> get _destinations {
    if (_isAdmin) {
      return const [
        NavigationDestination(
          icon: Icon(Icons.hub_rounded),
          selectedIcon: Icon(Icons.hub),
          label: 'Allocation',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_add_alt_1_outlined),
          selectedIcon: Icon(Icons.badge_rounded),
          label: 'Register',
        ),
        NavigationDestination(
          icon: Icon(Icons.face_retouching_natural),
          selectedIcon: Icon(Icons.verified_user),
          label: 'Attendance',
        ),
        NavigationDestination(
          icon: Icon(Icons.gavel_rounded),
          selectedIcon: Icon(Icons.warning_amber_rounded),
          label: 'Malpractice',
        ),
        NavigationDestination(
          icon: Icon(Icons.account_circle_outlined),
          selectedIcon: Icon(Icons.account_circle),
          label: 'Profile',
        ),
      ];
    }

    if (_isDisciplinaryOfficer) {
      return const [
        NavigationDestination(
          icon: Icon(Icons.assignment_late_outlined),
          selectedIcon: Icon(Icons.assignment_late),
          label: 'Cases',
        ),
        NavigationDestination(
          icon: Icon(Icons.account_circle_outlined),
          selectedIcon: Icon(Icons.account_circle),
          label: 'Profile',
        ),
      ];
    }

    return const [
      NavigationDestination(
        icon: Icon(Icons.assignment_ind_outlined),
        selectedIcon: Icon(Icons.assignment_ind),
        label: 'Assignment',
      ),
      NavigationDestination(
        icon: Icon(Icons.person_add_alt_1_outlined),
        selectedIcon: Icon(Icons.badge_rounded),
        label: 'Register',
      ),
      NavigationDestination(
        icon: Icon(Icons.face_retouching_natural),
        selectedIcon: Icon(Icons.verified_user),
        label: 'Attendance',
      ),
      NavigationDestination(
        icon: Icon(Icons.gavel_rounded),
        selectedIcon: Icon(Icons.warning_amber_rounded),
        label: 'Malpractice',
      ),
      NavigationDestination(
        icon: Icon(Icons.account_circle_outlined),
        selectedIcon: Icon(Icons.account_circle),
        label: 'Profile',
      ),
    ];
  }

  int get _unreadNotificationCount =>
      _notifications.where((notification) => !notification.isRead).length;

  List<NavigationRailDestination> get _railDestinations => _destinations
      .map(
        (destination) => NavigationRailDestination(
          icon: destination.icon,
          selectedIcon: destination.selectedIcon ?? destination.icon,
          label: Text(destination.label),
        ),
      )
      .toList();

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    if (_isLoadingNotifications) {
      return;
    }

    setState(() => _isLoadingNotifications = true);
    try {
      final notifications = await ApiService.instance.fetchNotifications(
        widget.currentUser,
      );
      if (mounted) {
        setState(() => _notifications = notifications);
      }
    } catch (_) {
      // Notifications are helpful, but they should not block the dashboard.
    } finally {
      if (mounted) {
        setState(() => _isLoadingNotifications = false);
      }
    }
  }

  Future<void> _openNotifications() async {
    await _loadNotifications();
    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _NotificationSheet(
        notifications: _notifications,
        onMarkRead: (notification) async {
          await ApiService.instance.markNotificationRead(notification.id);
          await _loadNotifications();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final useNavigationRail = screenWidth >= 900;
    final roleLabel = widget.currentUser.role.label;
    final username = widget.currentUser.username;
    final shouldCollapseTitle =
        roleLabel.toLowerCase() == username.toLowerCase();
    final appBarTitle = shouldCollapseTitle
        ? roleLabel
        : '$roleLabel - $username';

    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: _openNotifications,
            icon: Badge(
              isLabelVisible: _unreadNotificationCount > 0,
              label: Text('$_unreadNotificationCount'),
              child: Icon(
                _unreadNotificationCount > 0
                    ? Icons.notifications_active
                    : Icons.notifications_none,
                color: colorScheme.primary,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Log out',
            onPressed: widget.onLogout,
            icon: Icon(Icons.logout_rounded, color: colorScheme.primary),
          ),
        ],
      ),
      body: useNavigationRail
          ? Row(
              children: [
                SafeArea(
                  child: NavigationRail(
                    extended: screenWidth >= 1180,
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: (index) =>
                        setState(() => _selectedIndex = index),
                    labelType: screenWidth >= 1180
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.selected,
                    destinations: _railDestinations,
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _pages[_selectedIndex]),
              ],
            )
          : _pages[_selectedIndex],
      bottomNavigationBar: useNavigationRail
          ? null
          : NavigationBar(
              height: screenWidth < 380 ? 68 : 78,
              labelBehavior: screenWidth < 380
                  ? NavigationDestinationLabelBehavior.onlyShowSelected
                  : NavigationDestinationLabelBehavior.alwaysShow,
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) =>
                  setState(() => _selectedIndex = index),
              destinations: _destinations,
            ),
    );
  }
}

class _NotificationSheet extends StatefulWidget {
  const _NotificationSheet({
    required this.notifications,
    required this.onMarkRead,
  });

  final List<AppNotification> notifications;
  final Future<void> Function(AppNotification notification) onMarkRead;

  @override
  State<_NotificationSheet> createState() => _NotificationSheetState();
}

class _NotificationSheetState extends State<_NotificationSheet> {
  late List<AppNotification> _notifications;

  @override
  void initState() {
    super.initState();
    _notifications = List.of(widget.notifications);
  }

  Future<void> _markRead(AppNotification notification) async {
    await widget.onMarkRead(notification);
    if (!mounted) {
      return;
    }

    setState(() {
      final index = _notifications.indexWhere(
        (item) => item.id == notification.id,
      );
      if (index != -1) {
        _notifications[index] = _notifications[index].copyWith(isRead: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.58,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                'Notifications',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (_notifications.isEmpty)
              const Expanded(
                child: Center(child: Text('No notifications yet.')),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: _notifications.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final notification = _notifications[index];
                    return Material(
                      color: notification.isRead
                          ? colorScheme.surface
                          : colorScheme.primaryContainer.withValues(
                              alpha: 0.38,
                            ),
                      borderRadius: BorderRadius.circular(8),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        leading: Icon(
                          notification.isRead
                              ? Icons.notifications_none
                              : Icons.notifications_active,
                          color: colorScheme.primary,
                        ),
                        title: Text(notification.title),
                        subtitle: Text(notification.message),
                        trailing: notification.isRead
                            ? null
                            : IconButton(
                                tooltip: 'Mark as read',
                                onPressed: () => _markRead(notification),
                                icon: const Icon(Icons.done_rounded),
                              ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
