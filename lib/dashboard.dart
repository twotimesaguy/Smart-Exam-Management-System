import 'package:flutter/material.dart';
import 'package:flutter_application_1/allocation_module.dart';
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
