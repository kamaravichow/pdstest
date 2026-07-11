import 'dart:math' as math;
import 'dart:ui' show AppExitType, PointerDeviceKind;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'rpicam.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartHomeApp());
}

/// Enables drag-to-scroll for touchscreens, mice, styluses, and trackpads.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.unknown,
  };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }
}

class SmartHomeApp extends StatelessWidget {
  const SmartHomeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Haven Smart Home',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const AppScrollBehavior(),
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.blue,
          surface: AppColors.card,
        ),
        fontFamily: 'Roboto',
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontSize: 40, fontWeight: FontWeight.w400),
          headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w400),
          titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
          titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          bodyLarge: TextStyle(fontSize: 16),
          bodyMedium: TextStyle(fontSize: 14, color: AppColors.muted),
        ),
        iconTheme: const IconThemeData(color: AppColors.muted),
        sliderTheme: SliderThemeData(
          activeTrackColor: AppColors.blue,
          inactiveTrackColor: AppColors.stroke,
          thumbColor: AppColors.blue,
          overlayColor: AppColors.blue.withValues(alpha: .16),
          trackHeight: 4,
        ),
      ),
      home: const SmartHomeDashboard(),
    );
  }
}

class AppColors {
  static const background = Color(0xFF0C0C0D);
  static const sidebar = Color(0xFF111112);
  static const card = Color(0xFF171718);
  static const cardRaised = Color(0xFF1E1E1F);
  static const stroke = Color(0xFF2A2A2C);
  static const white = Color(0xFFF5F5F7);
  static const muted = Color(0xFF98989F);
  static const blue = Color(0xFF0A84FF);
  static const red = Color(0xFFFF453A);
  static const yellow = Color(0xFFFFD60A);
  static const green = Color(0xFF30D158);
}

enum DashboardSection { home, camera, rooms, devices, automation, energy }

class SmartHomeDashboard extends StatefulWidget {
  const SmartHomeDashboard({super.key});

  @override
  State<SmartHomeDashboard> createState() => _SmartHomeDashboardState();
}

class _SmartHomeDashboardState extends State<SmartHomeDashboard> {
  DashboardSection _section = DashboardSection.home;
  final TextEditingController _searchController = TextEditingController();
  final Map<String, bool> _devicePower = {
    'Smart CCTV': true,
    'halo2': true,
    'SØMLØS S1': true,
    'Philips US': false,
    'Google Thermostat': true,
  };
  double _lightIntensity = .72;
  double _musicProgress = .18;
  bool _playing = true;
  String _onTime = '05:00 PM';
  String _offTime = '06:00 AM';
  int _selectedForecast = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggle(String name) {
    setState(() => _devicePower[name] = !(_devicePower[name] ?? false));
  }

  void _selectSection(DashboardSection section) {
    setState(() => _section = section);
  }

  void _onHorizontalSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 420) return;
    final values = DashboardSection.values;
    final index = _section.index;
    if (velocity < 0 && index < values.length - 1) {
      _selectSection(values[index + 1]);
    } else if (velocity > 0 && index > 0) {
      _selectSection(values[index - 1]);
    }
  }

  Future<void> _closeSoftware() async {
    // Quits the process on Linux/desktop while staying in fullscreen until exit.
    await WidgetsBinding.instance.exitApplication(AppExitType.required);
    // Fallback if the platform cancelled the exit request.
    await SystemNavigator.pop();
  }

  void _showSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.cardRaised,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Settings',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                const Text(
                  'App stays fullscreen. Use Close software to quit.',
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 18),
                ListTile(
                  key: const Key('close-software'),
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AppColors.red.withValues(alpha: .18),
                    child: const Icon(
                      Icons.power_settings_new_rounded,
                      color: AppColors.red,
                    ),
                  ),
                  title: const Text('Close software'),
                  subtitle: const Text('Quit Haven and leave fullscreen'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    Navigator.pop(context);
                    await _closeSoftware();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAddDevice() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.cardRaised,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add a device',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose a nearby device to connect.',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 18),
              for (final item in const [
                (
                  Icons.lightbulb_outline_rounded,
                  'Living room light',
                  'Matter • Ready to pair',
                ),
                (
                  Icons.sensors_rounded,
                  'Hallway sensor',
                  'Zigbee • Ready to pair',
                ),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: AppColors.stroke,
                    child: Icon(item.$1, color: AppColors.white),
                  ),
                  title: Text(item.$2),
                  subtitle: Text(item.$3),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: Text('${item.$2} is ready to configure.'),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isNarrow = width < 640;
        final isDesktop = width >= 1180;
        final railWidth = isNarrow ? 0.0 : (width < 900 ? 64.0 : 76.0);

        return Scaffold(
          // SafeArea + ClipRect keep the UI inside the visible screen bounds
          // on fullscreen kiosk panels. In narrow (bottom-nav) mode the close
          // control lives inside the header rows rather than floating above
          // them, so it never covers the settings or camera buttons.
          body: SafeArea(
            child: ClipRect(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragEnd: _onHorizontalSwipe,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!isNarrow)
                      _NavigationRail(
                        width: railWidth,
                        compactHeight: constraints.maxHeight < 700,
                        selected: _section,
                        onSelected: _selectSection,
                        onOpenSettings: _showSettings,
                        onClose: _closeSoftware,
                      ),
                    Expanded(
                      child: _section == DashboardSection.camera
                          ? _CameraPage(
                              isNarrow: isNarrow,
                              onClose: isNarrow ? _closeSoftware : null,
                            )
                          : _DashboardScrollView(
                              isDesktop: isDesktop,
                              isNarrow: isNarrow,
                              searchController: _searchController,
                              onAddDevice: _showAddDevice,
                              onOpenSettings: isNarrow ? _showSettings : null,
                              onClose: isNarrow ? _closeSoftware : null,
                              power: _devicePower,
                              onToggle: _toggle,
                              lightIntensity: _lightIntensity,
                              onLightChanged: (value) =>
                                  setState(() => _lightIntensity = value),
                              musicProgress: _musicProgress,
                              playing: _playing,
                              onMusicChanged: (value) =>
                                  setState(() => _musicProgress = value),
                              onPlayToggle: () =>
                                  setState(() => _playing = !_playing),
                              onTime: _onTime,
                              offTime: _offTime,
                              onOnTimeChanged: (value) =>
                                  setState(() => _onTime = value),
                              onOffTimeChanged: (value) =>
                                  setState(() => _offTime = value),
                              selectedForecast: _selectedForecast,
                              onForecastSelected: (value) =>
                                  setState(() => _selectedForecast = value),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          bottomNavigationBar: isNarrow
              ? NavigationBar(
                  backgroundColor: AppColors.sidebar,
                  indicatorColor: AppColors.cardRaised,
                  selectedIndex: _section.index,
                  onDestinationSelected: (index) =>
                      _selectSection(DashboardSection.values[index]),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home_rounded),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.videocam_outlined),
                      selectedIcon: Icon(Icons.videocam_rounded),
                      label: 'Camera',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.meeting_room_outlined),
                      label: 'Rooms',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.devices_other_outlined),
                      label: 'Devices',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.auto_awesome_outlined),
                      label: 'Scenes',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.bolt_outlined),
                      label: 'Energy',
                    ),
                  ],
                )
              : null,
        );
      },
    );
  }
}

class _NavigationRail extends StatelessWidget {
  const _NavigationRail({
    required this.width,
    required this.compactHeight,
    required this.selected,
    required this.onSelected,
    required this.onOpenSettings,
    required this.onClose,
  });

  final double width;
  final bool compactHeight;
  final DashboardSection selected;
  final ValueChanged<DashboardSection> onSelected;
  final VoidCallback onOpenSettings;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    const entries = [
      (DashboardSection.home, Icons.grid_view_rounded, 'Overview'),
      (DashboardSection.camera, Icons.videocam_rounded, 'Camera'),
      (DashboardSection.rooms, Icons.cast_connected_rounded, 'Rooms'),
      (DashboardSection.devices, Icons.devices_other_rounded, 'Devices'),
      (DashboardSection.automation, Icons.auto_awesome_rounded, 'Automation'),
      (DashboardSection.energy, Icons.bar_chart_rounded, 'Energy'),
    ];

    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: AppColors.sidebar,
        border: Border(right: BorderSide(color: AppColors.stroke)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 14),
          // Close/exit sits where the home logo used to, so quitting the
          // kiosk is always one tap away.
          _CloseSoftwareButton(onPressed: onClose),
          SizedBox(height: compactHeight ? 8 : 18),
          for (final entry in entries)
            Padding(
              padding: EdgeInsets.symmetric(vertical: compactHeight ? 0 : 3),
              child: Tooltip(
                message: entry.$3,
                child: IconButton(
                  onPressed: () => onSelected(entry.$1),
                  style: IconButton.styleFrom(
                    minimumSize: Size(48, compactHeight ? 44 : 48),
                    backgroundColor: selected == entry.$1
                        ? AppColors.cardRaised
                        : Colors.transparent,
                    foregroundColor: selected == entry.$1
                        ? AppColors.white
                        : AppColors.muted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: Icon(entry.$2),
                ),
              ),
            ),
          const Spacer(),
          if (!compactHeight) ...[
            _StatusDot(color: AppColors.green),
            const SizedBox(height: 12),
            _StatusDot(color: const Color(0xFF64B5F6)),
            const SizedBox(height: 12),
            _StatusDot(color: AppColors.red),
            const SizedBox(height: 12),
            _StatusDot(color: const Color(0xFFFFD166)),
            const Spacer(),
          ],
          if (!compactHeight) ...[
            IconButton(
              tooltip: 'Messages',
              onPressed: () {},
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 21),
            ),
            IconButton(
              tooltip: 'Security',
              onPressed: () {},
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              icon: const Icon(Icons.shield_outlined, size: 21),
            ),
          ],
          IconButton(
            key: const Key('open-settings'),
            tooltip: 'Settings',
            onPressed: onOpenSettings,
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            icon: const Icon(Icons.settings_outlined, size: 21),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _DashboardScrollView extends StatelessWidget {
  const _DashboardScrollView({
    required this.isDesktop,
    required this.isNarrow,
    required this.searchController,
    required this.onAddDevice,
    this.onOpenSettings,
    this.onClose,
    required this.power,
    required this.onToggle,
    required this.lightIntensity,
    required this.onLightChanged,
    required this.musicProgress,
    required this.playing,
    required this.onMusicChanged,
    required this.onPlayToggle,
    required this.onTime,
    required this.offTime,
    required this.onOnTimeChanged,
    required this.onOffTimeChanged,
    required this.selectedForecast,
    required this.onForecastSelected,
  });

  final bool isDesktop;
  final bool isNarrow;
  final TextEditingController searchController;
  final VoidCallback onAddDevice;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onClose;
  final Map<String, bool> power;
  final ValueChanged<String> onToggle;
  final double lightIntensity;
  final ValueChanged<double> onLightChanged;
  final double musicProgress;
  final bool playing;
  final ValueChanged<double> onMusicChanged;
  final VoidCallback onPlayToggle;
  final String onTime;
  final String offTime;
  final ValueChanged<String> onOnTimeChanged;
  final ValueChanged<String> onOffTimeChanged;
  final int selectedForecast;
  final ValueChanged<int> onForecastSelected;

  @override
  Widget build(BuildContext context) {
    final horizontal = isNarrow ? 16.0 : 24.0;
    // Extra bottom padding guarantees the last card clears the screen edge (and
    // the bottom navigation bar in narrow mode) so the list scrolls to the end.
    final bottom = 32.0 + MediaQuery.viewPaddingOf(context).bottom;
    return CustomScrollView(
      key: const Key('dashboard-scroll'),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(horizontal, 18, horizontal, bottom),
          sliver: SliverList.list(
            children: [
              _DashboardHeader(
                controller: searchController,
                isNarrow: isNarrow,
                onAddDevice: onAddDevice,
                onOpenSettings: onOpenSettings,
                onClose: onClose,
              ),
              const SizedBox(height: 16),
              if (isDesktop)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 8,
                      child: _DeviceColumn(
                        power: power,
                        onToggle: onToggle,
                        lightIntensity: lightIntensity,
                        onLightChanged: onLightChanged,
                        musicProgress: musicProgress,
                        playing: playing,
                        onMusicChanged: onMusicChanged,
                        onPlayToggle: onPlayToggle,
                        onTime: onTime,
                        offTime: offTime,
                        onOnTimeChanged: onOnTimeChanged,
                        onOffTimeChanged: onOffTimeChanged,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      flex: 5,
                      child: _InsightColumn(
                        selectedForecast: selectedForecast,
                        onForecastSelected: onForecastSelected,
                      ),
                    ),
                  ],
                )
              else ...[
                _DeviceColumn(
                  power: power,
                  onToggle: onToggle,
                  lightIntensity: lightIntensity,
                  onLightChanged: onLightChanged,
                  musicProgress: musicProgress,
                  playing: playing,
                  onMusicChanged: onMusicChanged,
                  onPlayToggle: onPlayToggle,
                  onTime: onTime,
                  offTime: offTime,
                  onOnTimeChanged: onOnTimeChanged,
                  onOffTimeChanged: onOffTimeChanged,
                ),
                const SizedBox(height: 18),
                _InsightColumn(
                  selectedForecast: selectedForecast,
                  onForecastSelected: onForecastSelected,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.controller,
    required this.isNarrow,
    required this.onAddDevice,
    this.onOpenSettings,
    this.onClose,
  });
  final TextEditingController controller;
  final bool isNarrow;
  final VoidCallback onAddDevice;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final search = TextField(
      key: const Key('device-search'),
      controller: controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search for device',
        hintStyle: const TextStyle(color: AppColors.muted),
        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.white),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                onPressed: controller.clear,
                icon: const Icon(Icons.close_rounded),
              )
            : null,
        filled: true,
        fillColor: AppColors.card,
        contentPadding: const EdgeInsets.symmetric(vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: const BorderSide(color: AppColors.stroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: const BorderSide(color: AppColors.stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: const BorderSide(color: AppColors.blue, width: 1.4),
        ),
      ),
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton.icon(
          key: const Key('add-device'),
          onPressed: onAddDevice,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.blue,
            foregroundColor: Colors.white,
            minimumSize: Size(isNarrow ? 48 : 150, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
          icon: const Icon(Icons.add_rounded),
          label: isNarrow
              ? const SizedBox.shrink()
              : const Text('Add Devices', style: TextStyle(fontSize: 16)),
        ),
        const SizedBox(width: 10),
        IconButton.filled(
          tooltip: 'Notifications',
          onPressed: () => ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('No new alerts.'))),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.card,
            foregroundColor: AppColors.white,
            side: const BorderSide(color: AppColors.stroke),
            fixedSize: const Size(50, 50),
          ),
          icon: const Badge(
            smallSize: 7,
            child: Icon(Icons.notifications_none_rounded),
          ),
        ),
        if (onOpenSettings != null) ...[
          const SizedBox(width: 10),
          IconButton.filled(
            key: const Key('open-settings'),
            tooltip: 'Settings',
            onPressed: onOpenSettings,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.card,
              foregroundColor: AppColors.white,
              side: const BorderSide(color: AppColors.stroke),
              fixedSize: const Size(50, 50),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
        if (onClose != null) ...[
          const SizedBox(width: 10),
          _CloseSoftwareButton(onPressed: onClose!),
        ],
      ],
    );

    return Column(
      children: [
        Row(
          children: [
            if (!isNarrow) Expanded(child: search) else Expanded(child: search),
            const SizedBox(width: 12),
            actions,
          ],
        ),
        if (!isNarrow) ...[const SizedBox(height: 14), const _Greeting()],
      ],
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Morning, Jordan',
              style: TextStyle(fontSize: 18, color: AppColors.white),
            ),
            SizedBox(height: 2),
            Text(
              'Thu, Apr 25 • 06:32 PM',
              style: TextStyle(color: AppColors.muted),
            ),
          ],
        ),
      ),
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.cardRaised,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.stroke),
        ),
        child: const Icon(Icons.person_rounded, color: AppColors.white),
      ),
    ],
  );
}

class _DeviceColumn extends StatelessWidget {
  const _DeviceColumn({
    required this.power,
    required this.onToggle,
    required this.lightIntensity,
    required this.onLightChanged,
    required this.musicProgress,
    required this.playing,
    required this.onMusicChanged,
    required this.onPlayToggle,
    required this.onTime,
    required this.offTime,
    required this.onOnTimeChanged,
    required this.onOffTimeChanged,
  });

  final Map<String, bool> power;
  final ValueChanged<String> onToggle;
  final double lightIntensity;
  final ValueChanged<double> onLightChanged;
  final double musicProgress;
  final bool playing;
  final ValueChanged<double> onMusicChanged;
  final VoidCallback onPlayToggle;
  final String onTime;
  final String offTime;
  final ValueChanged<String> onOnTimeChanged;
  final ValueChanged<String> onOffTimeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CameraCard(
          isOn: power['Smart CCTV']!,
          onToggle: () => onToggle('Smart CCTV'),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 560;
            final cards = [
              _BatteryDeviceCard(
                name: 'halo2',
                subtitle: 'Bluetooth Speaker',
                battery: 72,
                image: 'assets/images/speaker.png',
                isOn: power['halo2']!,
                onToggle: () => onToggle('halo2'),
              ),
              _BatteryDeviceCard(
                name: 'SØMLØS S1',
                subtitle: 'Robotic Cleaner',
                battery: 52,
                image: 'assets/images/robot-vacuum.png',
                isOn: power['SØMLØS S1']!,
                onToggle: () => onToggle('SØMLØS S1'),
              ),
            ];
            return twoColumns
                ? Row(
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 14),
                      Expanded(child: cards[1]),
                    ],
                  )
                : Column(
                    children: [cards[0], const SizedBox(height: 14), cards[1]],
                  );
          },
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 680;
            final light = _LightCard(
              isOn: power['Philips US']!,
              value: lightIntensity,
              onToggle: () => onToggle('Philips US'),
              onChanged: onLightChanged,
            );
            final schedule = _ScheduleCard(
              onTime: onTime,
              offTime: offTime,
              onOnTimeChanged: onOnTimeChanged,
              onOffTimeChanged: onOffTimeChanged,
            );
            return twoColumns
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 4, child: light),
                      const SizedBox(width: 14),
                      Expanded(flex: 6, child: schedule),
                    ],
                  )
                : Column(
                    children: [light, const SizedBox(height: 14), schedule],
                  );
          },
        ),
        const SizedBox(height: 14),
        _MusicCard(
          progress: musicProgress,
          playing: playing,
          onChanged: onMusicChanged,
          onPlayToggle: onPlayToggle,
        ),
      ],
    );
  }
}

class _CameraCard extends StatelessWidget {
  const _CameraCard({required this.isOn, required this.onToggle});
  final bool isOn;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return _Card(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: _CardTitle(title: 'Smart CCTV', subtitle: 'Camera'),
              ),
              _PowerButton(isOn: isOn, onPressed: onToggle),
            ],
          ),
          const SizedBox(height: 14),
          Opacity(
            opacity: isOn ? 1 : .34,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final sideBySide = constraints.maxWidth >= 520;
                final first = const _CameraFeed(
                  asset: 'assets/images/camera-entry.png',
                  alignment: Alignment.center,
                );
                final second = const _CameraFeed(
                  asset: 'assets/images/camera-living-room.png',
                  alignment: Alignment.center,
                );
                return sideBySide
                    ? Row(
                        children: [
                          Expanded(child: first),
                          const SizedBox(width: 12),
                          Expanded(child: second),
                        ],
                      )
                    : Column(
                        children: [first, const SizedBox(height: 12), second],
                      );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraFeed extends StatelessWidget {
  const _CameraFeed({required this.asset, required this.alignment});
  final String asset;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 16 / 9,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(asset, fit: BoxFit.cover, alignment: alignment),
          Positioned(
            left: 10,
            top: 10,
            child: _Pill(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text('Live'),
                ],
              ),
            ),
          ),
          const Positioned(
            right: 10,
            top: 10,
            child: _Pill(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('FHD'),
                  SizedBox(width: 3),
                  Icon(Icons.keyboard_arrow_down_rounded, size: 17),
                ],
              ),
            ),
          ),
          Positioned(
            right: 10,
            bottom: 10,
            child: _Pill(
              onTap: () => showDialog<void>(
                context: context,
                builder: (context) => Dialog.fullscreen(
                  backgroundColor: AppColors.background,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Image.asset(asset, fit: BoxFit.contain),
                      ),
                      Positioned(
                        right: 16,
                        top: 16,
                        child: IconButton.filled(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_fullscreen_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Full Screen'),
                  SizedBox(width: 5),
                  Icon(Icons.fullscreen_rounded, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xB8525252),
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: child,
      ),
    ),
  );
}

class _BatteryDeviceCard extends StatelessWidget {
  const _BatteryDeviceCard({
    required this.name,
    required this.subtitle,
    required this.battery,
    required this.image,
    required this.isOn,
    required this.onToggle,
  });
  final String name;
  final String subtitle;
  final int battery;
  final String image;
  final bool isOn;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 220,
    child: _Card(
      padding: EdgeInsets.zero,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Opacity(
                opacity: isOn ? 1 : .35,
                child: Image.asset(image, fit: BoxFit.cover),
              ),
            ),
          ),
          Positioned(
            left: 14,
            top: 14,
            right: 58,
            child: _CardTitle(title: name, subtitle: subtitle),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: _PowerButton(isOn: isOn, onPressed: onToggle),
          ),
          Positioned(
            left: 14,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$battery%',
                  style: const TextStyle(
                    fontSize: 42,
                    height: 1,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: 11),
                const Row(
                  children: [
                    Icon(
                      Icons.battery_5_bar_rounded,
                      color: AppColors.white,
                      size: 19,
                    ),
                    SizedBox(width: 5),
                    Text('Battery'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _LightCard extends StatelessWidget {
  const _LightCard({
    required this.isOn,
    required this.value,
    required this.onToggle,
    required this.onChanged,
  });
  final bool isOn;
  final double value;
  final VoidCallback onToggle;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      children: [
        Row(
          children: [
            const Expanded(
              child: _CardTitle(title: 'Philips US', subtitle: 'Smart Light'),
            ),
            _PowerButton(isOn: isOn, onPressed: onToggle),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Icon(
              Icons.light_mode_outlined,
              color: AppColors.white,
              size: 20,
            ),
            const SizedBox(width: 7),
            const Text('Intensity'),
            const Spacer(),
            Text(
              '${(value * 100).round()}%',
              style: const TextStyle(fontSize: 18),
            ),
          ],
        ),
        Slider(
          key: const Key('light-slider'),
          value: value,
          onChanged: isOn ? onChanged : null,
        ),
      ],
    ),
  );
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({
    required this.onTime,
    required this.offTime,
    required this.onOnTimeChanged,
    required this.onOffTimeChanged,
  });
  final String onTime;
  final String offTime;
  final ValueChanged<String> onOnTimeChanged;
  final ValueChanged<String> onOffTimeChanged;

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Expanded(
              child: _CardTitle(
                title: 'Smart Energy',
                subtitle: 'Set device work schedule',
              ),
            ),
            Icon(Icons.more_vert_rounded, color: AppColors.white),
          ],
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final items = [
              _TimeDropdown(
                label: 'On at:',
                value: onTime,
                onChanged: onOnTimeChanged,
              ),
              _TimeDropdown(
                label: 'Off at:',
                value: offTime,
                onChanged: onOffTimeChanged,
              ),
            ];
            return constraints.maxWidth > 400
                ? Row(
                    children: [
                      Expanded(child: items[0]),
                      const SizedBox(width: 10),
                      Expanded(child: items[1]),
                    ],
                  )
                : Column(
                    children: [items[0], const SizedBox(height: 10), items[1]],
                  );
          },
        ),
      ],
    ),
  );
}

class _TimeDropdown extends StatelessWidget {
  const _TimeDropdown({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  static const values = [
    '05:00 PM',
    '06:00 PM',
    '09:00 PM',
    '06:00 AM',
    '07:00 AM',
  ];

  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    padding: const EdgeInsets.only(left: 12),
    decoration: BoxDecoration(
      color: AppColors.cardRaised,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      children: [
        Text(label, style: const TextStyle(color: AppColors.muted)),
        const SizedBox(width: 6),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: AppColors.cardRaised,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              items: values
                  .map(
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Text(item, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) onChanged(value);
              },
            ),
          ),
        ),
      ],
    ),
  );
}

class _MusicCard extends StatelessWidget {
  const _MusicCard({
    required this.progress,
    required this.playing,
    required this.onChanged,
    required this.onPlayToggle,
  });
  final double progress;
  final bool playing;
  final ValueChanged<double> onChanged;
  final VoidCallback onPlayToggle;

  @override
  Widget build(BuildContext context) => _Card(
    child: Row(
      children: [
        IconButton.filled(
          onPressed: onPlayToggle,
          style: IconButton.styleFrom(
            backgroundColor: AppColors.cardRaised,
            foregroundColor: AppColors.white,
          ),
          icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        ),
        const SizedBox(width: 10),
        const Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'a lot',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 3),
              Text(
                '21 Savage ft. J. Cole',
                style: TextStyle(color: AppColors.muted),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Expanded(
          flex: 5,
          child: Slider(value: progress, onChanged: onChanged),
        ),
        Text(
          _formatDuration(progress * 283),
          style: const TextStyle(color: AppColors.muted),
        ),
      ],
    ),
  );

  static String _formatDuration(double seconds) {
    final whole = seconds.round();
    return '${whole ~/ 60}:${(whole % 60).toString().padLeft(2, '0')}';
  }
}

class _InsightColumn extends StatelessWidget {
  const _InsightColumn({
    required this.selectedForecast,
    required this.onForecastSelected,
  });
  final int selectedForecast;
  final ValueChanged<int> onForecastSelected;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const _WeatherCard(),
      const SizedBox(height: 18),
      _ForecastSection(
        selected: selectedForecast,
        onSelected: onForecastSelected,
      ),
      const SizedBox(height: 18),
      const _PowerStatistics(),
    ],
  );
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard();

  @override
  Widget build(BuildContext context) => _Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Weather', style: TextStyle(fontSize: 23)),
        const SizedBox(height: 7),
        const Row(
          children: [
            Icon(Icons.location_on_outlined, size: 19),
            SizedBox(width: 5),
            Text('Ożarów Mazowiecki', style: TextStyle(color: AppColors.muted)),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Text(
              '24°',
              style: TextStyle(
                fontSize: 54,
                fontWeight: FontWeight.w300,
                height: 1,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'Mostly Clear',
                style: TextStyle(color: AppColors.muted),
              ),
            ),
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.yellow.withValues(alpha: .12),
                    shape: BoxShape.circle,
                  ),
                ),
                const Icon(
                  Icons.wb_cloudy_rounded,
                  size: 68,
                  color: AppColors.yellow,
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

class _ForecastSection extends StatelessWidget {
  const _ForecastSection({required this.selected, required this.onSelected});
  final int selected;
  final ValueChanged<int> onSelected;

  static const entries = [
    ('Wed', Icons.wb_cloudy_rounded, '10°', AppColors.yellow),
    ('Fri', Icons.thunderstorm_rounded, '15°', Color(0xFF64D2FF)),
    ('Sat', Icons.cloud_rounded, '12°', AppColors.muted),
    ('Sun', Icons.wb_sunny_rounded, '19°', AppColors.yellow),
    ('Mon', Icons.water_drop_rounded, '10°', Color(0xFF64D2FF)),
  ];

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Row(
        children: [
          Expanded(child: Text('Forecast', style: TextStyle(fontSize: 23))),
          Text('Next 7 days'),
        ],
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          final width = math.max(78.0, (constraints.maxWidth - 32) / 5);
          return SizedBox(
            height: 132,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = entries[index];
                return SizedBox(
                  width: width,
                  child: Material(
                    color: selected == index
                        ? const Color(0xFF262628)
                        : AppColors.card,
                    borderRadius: BorderRadius.circular(15),
                    child: InkWell(
                      onTap: () => onSelected(index),
                      borderRadius: BorderRadius.circular(15),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        child: Column(
                          children: [
                            Text(
                              item.$1,
                              style: const TextStyle(color: AppColors.muted),
                            ),
                            const Spacer(),
                            Icon(item.$2, color: item.$4, size: 34),
                            const Spacer(),
                            Text(item.$3, style: const TextStyle(fontSize: 19)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    ],
  );
}

class _PowerStatistics extends StatelessWidget {
  const _PowerStatistics();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Row(
        children: [
          Expanded(
            child: Text('Power Statistics', style: TextStyle(fontSize: 23)),
          ),
          Text('Last Month'),
        ],
      ),
      const SizedBox(height: 12),
      _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Consumption Expense', style: TextStyle(fontSize: 21)),
            const SizedBox(height: 4),
            const Text(
              'See power expense here!',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 15),
            SizedBox(
              height: 285,
              width: double.infinity,
              child: CustomPaint(painter: _PowerChartPainter()),
            ),
          ],
        ),
      ),
    ],
  );
}

class _PowerChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final labelPainter = TextPainter(textDirection: TextDirection.ltr);
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug'];
    const bars = [88.0, 74.0, 94.0, 116.0, 54.0, 76.0, 70.0, 52.0];
    final chartBottom = size.height - 28;
    const chartTop = 16.0;
    const left = 28.0;
    final step = (size.width - left - 8) / months.length;
    final barPaint = Paint()..strokeCap = StrokeCap.round;

    for (var i = 0; i < months.length; i++) {
      final x = left + step * i + step / 2;
      final height = bars[i] / 130 * (chartBottom - chartTop);
      barPaint
        ..color = i == 3 ? AppColors.blue : const Color(0xFF464648)
        ..strokeWidth = 6;
      canvas.drawLine(
        Offset(x, chartBottom),
        Offset(x, chartBottom - height),
        barPaint,
      );
      labelPainter.text = TextSpan(
        text: months[i],
        style: TextStyle(
          color: i == 3 ? AppColors.white : AppColors.muted,
          fontSize: 12,
        ),
      );
      labelPainter.layout();
      labelPainter.paint(
        canvas,
        Offset(x - labelPainter.width / 2, chartBottom + 11),
      );
    }

    final linePaint = Paint()
      ..color = AppColors.blue.withValues(alpha: .7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path();
    const lineValues = [148.0, 120.0, 155.0, 168.0, 118.0, 105.0, 132.0, 108.0];
    for (var i = 0; i < lineValues.length; i++) {
      final x = left + step * i + step / 2;
      final y =
          chartBottom - (lineValues[i] - 80) / 100 * (chartBottom - chartTop);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);
    final selectedX = left + step * 3 + step / 2;
    final selectedY =
        chartBottom - (lineValues[3] - 80) / 100 * (chartBottom - chartTop);
    canvas.drawCircle(
      Offset(selectedX, selectedY),
      5,
      Paint()..color = AppColors.white,
    );
    canvas.drawCircle(
      Offset(selectedX, selectedY),
      3,
      Paint()..color = AppColors.blue,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(15)});
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.stroke.withValues(alpha: .8)),
    ),
    padding: padding,
    child: child,
  );
}

class _CardTitle extends StatelessWidget {
  const _CardTitle({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 21, color: AppColors.white),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        style: const TextStyle(fontSize: 14, color: AppColors.muted),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ],
  );
}

class _CloseSoftwareButton extends StatelessWidget {
  const _CloseSoftwareButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filled(
    key: const Key('close-software-quick'),
    tooltip: 'Close software',
    onPressed: onPressed,
    style: IconButton.styleFrom(
      fixedSize: const Size(40, 40),
      backgroundColor: AppColors.red.withValues(alpha: .18),
      foregroundColor: AppColors.red,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    icon: const Icon(Icons.power_settings_new_rounded, size: 22),
  );
}

class _PowerButton extends StatelessWidget {
  const _PowerButton({required this.isOn, required this.onPressed});
  final bool isOn;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filled(
    key: ValueKey('power-$isOn'),
    tooltip: isOn ? 'Turn off' : 'Turn on',
    onPressed: onPressed,
    style: IconButton.styleFrom(
      fixedSize: const Size(44, 44),
      backgroundColor: AppColors.cardRaised,
      foregroundColor: isOn ? AppColors.blue : AppColors.muted,
    ),
    icon: const Icon(Icons.power_settings_new_rounded, size: 22),
  );
}

/// Live preview from a hardware camera attached to the device.
///
/// Two capture paths, tried in order:
///
/// 1. rpicam (libcamera) via [RpicamFeed] — Raspberry Pi CSI camera modules.
///    Their /dev/video* nodes are raw unicam/ISP interfaces that the plugin's
///    GStreamer `v4l2src` pipeline can open but never get frames from, so the
///    plugin is not usable for them; `rpicam-vid` is.
/// 2. The `camera` plugin (V4L2 on Linux for USB webcams, AVFoundation on
///    macOS, Media Foundation on Windows via `camera_desktop`).
///
/// Whichever path is active is released whenever this page leaves the tree or
/// the app is backgrounded, so the camera is only held while the tab is
/// visible.
class _CameraPage extends StatefulWidget {
  const _CameraPage({required this.isNarrow, this.onClose});
  final bool isNarrow;
  final VoidCallback? onClose;

  @override
  State<_CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<_CameraPage> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  RpicamStack? _rpicam;
  RpicamFeed? _feed;
  int _index = 0;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setUp();
  }

  Future<void> _setUp() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    _disposeFeedSoon();
    _rpicam = null;
    // Prefer the Pi camera stack: CSI modules can't deliver frames through
    // the plugin's V4L2 pipeline. Falls through to the plugin for USB webcams
    // and other platforms.
    final rpicam = await detectRpicam();
    if (!mounted) return;
    if (rpicam != null) {
      _rpicam = rpicam;
      await _openRpicamFeed(_index.clamp(0, rpicam.cameras.length - 1));
      return;
    }
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      _cameras = cameras;
      if (cameras.isEmpty) {
        setState(() {
          _busy = false;
          _error = 'No camera detected on this device.';
        });
        return;
      }
      await _openCamera(_index.clamp(0, cameras.length - 1));
    } on CameraException catch (e) {
      if (mounted) setState(() => _fail(e));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not access the camera: $e';
        });
      }
    }
  }

  /// Combinations to try when opening a camera, from best quality to most
  /// compatible. Not every camera can negotiate/allocate a buffer for a given
  /// resolution + pixel format (a raw V4L2 source may fail with "Failed to
  /// allocate required memory" at 720p, or only expose MJPEG at some sizes),
  /// so we fall back through safer options instead of hardcoding one.
  static const _openAttempts = <(ResolutionPreset, ImageFormatGroup?)>[
    (ResolutionPreset.high, ImageFormatGroup.jpeg),
    (ResolutionPreset.high, null),
    (ResolutionPreset.medium, ImageFormatGroup.jpeg),
    (ResolutionPreset.medium, null),
    (ResolutionPreset.low, null),
  ];

  Future<void> _openCamera(int index) async {
    final previous = _controller;
    _controller = null;
    await previous?.dispose();

    CameraException? lastError;
    for (final (preset, format) in _openAttempts) {
      final controller = CameraController(
        _cameras[index],
        preset,
        enableAudio: false,
        imageFormatGroup: format,
      );
      try {
        await controller.initialize();
        if (!mounted) {
          await controller.dispose();
          return;
        }
        setState(() {
          _controller = controller;
          _index = index;
          _busy = false;
          _error = null;
        });
        return;
      } on CameraException catch (e) {
        await controller.dispose();
        lastError = e;
        // A denied/restricted permission won't be fixed by retrying with a
        // different resolution, so stop early.
        if (e.code == 'CameraAccessDenied' ||
            e.code == 'CameraAccessDeniedWithoutPrompt' ||
            e.code == 'CameraAccessRestricted') {
          break;
        }
      }
    }
    if (mounted && lastError != null) setState(() => _fail(lastError!));
  }

  Future<void> _openRpicamFeed(int index) async {
    _disposeFeedSoon();
    final rpicam = _rpicam!;
    final feed = RpicamFeed(
      binary: rpicam.binary,
      camera: rpicam.cameras[index],
    );
    feed.addListener(_onFeedChanged);
    setState(() {
      _feed = feed;
      _index = index;
    });
    await feed.start();
  }

  /// The feed notifies on every decoded frame; only rebuild the page when its
  /// readiness or error state changes (the preview repaints itself).
  void _onFeedChanged() {
    if (!mounted) return;
    final feed = _feed;
    if (feed == null) return;
    final busy = feed.image == null && feed.error == null;
    if (busy != _busy || feed.error != _error) {
      setState(() {
        _busy = busy;
        _error = feed.error;
      });
    }
  }

  /// Releases the camera process immediately, but defers disposing the feed
  /// itself until after the next frame so any [RpicamPreview] still in the
  /// tree has unsubscribed first.
  void _disposeFeedSoon() {
    final feed = _feed;
    if (feed == null) return;
    feed.removeListener(_onFeedChanged);
    _feed = null;
    feed.stop();
    WidgetsBinding.instance.addPostFrameCallback((_) => feed.dispose());
  }

  void _fail(CameraException e) {
    _busy = false;
    switch (e.code) {
      case 'CameraAccessDenied':
      case 'CameraAccessDeniedWithoutPrompt':
      case 'CameraAccessRestricted':
        _error = 'Camera access was denied. Grant camera permission to view '
            'the live feed.';
      default:
        _error = e.description ?? e.code;
    }
  }

  int get _switchableCameraCount =>
      _rpicam?.cameras.length ?? _cameras.length;

  Future<void> _switchCamera() async {
    if (_switchableCameraCount < 2 || _busy) return;
    setState(() => _busy = true);
    final rpicam = _rpicam;
    if (rpicam != null) {
      await _openRpicamFeed((_index + 1) % rpicam.cameras.length);
    } else {
      await _openCamera((_index + 1) % _cameras.length);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final controller = _controller;
      if (controller != null) {
        _controller = null;
        controller.dispose();
      }
      _disposeFeedSoon();
    } else if (state == AppLifecycleState.resumed &&
        _controller == null &&
        _feed == null) {
      _setUp();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _disposeFeedSoon();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final horizontal = widget.isNarrow ? 16.0 : 24.0;
    final controller = _controller;
    final feed = _feed;
    final ready = !_busy &&
        _error == null &&
        (feed != null
            ? feed.image != null
            : controller != null && controller.value.isInitialized);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(horizontal, 18, horizontal, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: _CardTitle(
                    title: 'Live Camera',
                    subtitle: 'Hardware camera feed',
                  ),
                ),
                if (_switchableCameraCount > 1)
                  IconButton.filled(
                    tooltip: 'Switch camera',
                    onPressed: _busy ? null : _switchCamera,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.card,
                      foregroundColor: AppColors.white,
                      side: const BorderSide(color: AppColors.stroke),
                      fixedSize: const Size(50, 50),
                    ),
                    icon: const Icon(Icons.cameraswitch_rounded),
                  ),
                if (widget.onClose != null) ...[
                  const SizedBox(width: 10),
                  _CloseSoftwareButton(onPressed: widget.onClose!),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _Card(
                padding: const EdgeInsets.all(14),
                child: Center(
                  child: ready ? _preview() : _placeholder(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _activeCameraName {
    final rpicam = _rpicam;
    if (rpicam != null) return rpicam.cameras[_index].name;
    return _cameras.isEmpty ? 'Camera' : _cameras[_index].name;
  }

  Widget _preview() {
    final feed = _feed;
    return AspectRatio(
      aspectRatio: feed?.aspectRatio ?? _controller!.value.aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (feed != null) RpicamPreview(feed) else CameraPreview(_controller!),
            Positioned(
              left: 12,
              top: 12,
              child: _Pill(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    _LiveDot(),
                    SizedBox(width: 6),
                    Text('Live'),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 12,
              top: 12,
              child: _Pill(child: Text(_activeCameraName)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    if (_busy) {
      return const SizedBox(
        width: 44,
        height: 44,
        child: CircularProgressIndicator(strokeWidth: 3),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.videocam_off_rounded,
          size: 46,
          color: AppColors.muted,
        ),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            _error ?? 'Camera unavailable.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _setUp,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.blue,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry'),
        ),
      ],
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) => Container(
    width: 7,
    height: 7,
    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
  );
}
