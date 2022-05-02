import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lfdi/components/window_buttons.dart';
import 'package:lfdi/constants.dart';
import 'package:lfdi/main.dart';
import 'package:lfdi/pages/about.dart';
import 'package:lfdi/pages/discord.dart';
import 'package:lfdi/pages/settings.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../utils/debounce.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with WindowListener, TrayListener {
  int index = 0;
  int trayClickCount = 0;

  late final void Function() resetClickCountDebounced;

  @override
  void initState() {
    windowManager.addListener(this);
    trayManager.addListener(this);

    resetClickCountDebounced = debounce(
      () => trayClickCount = 0,
      const Duration(milliseconds: 500),
    );

    initTray();

    super.initState();
  }

  @override
  void dispose() {
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  // tray functions
  Future<void> initTray() async {
    await trayManager.setIcon(
      Platform.isWindows
          ? 'assets/images/app_icon.ico'
          : 'assets/images/lastfm discord smol.png',
    );
    await Future.delayed(const Duration(milliseconds: 200));
    await trayManager.setContextMenu(trayMenuItems);
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'restore_window':
        windowManager.isVisible().then(
          (value) async {
            if (value) {
              await windowManager.minimize();
              await windowManager.hide();

              return;
            }

            await windowManager.show();
            await windowManager.focus();
          },
        );
        break;
      case 'close_window':
        final rpc = ref.read(rpcProvider);

        rpc.dispose();
        trayManager.removeListener(this);
        trayManager.destroy();
        windowManager.destroy();
        break;
      default:
    }
  }

  @override
  void onTrayIconMouseDown() async {
    trayClickCount++;
    resetClickCountDebounced();

    if (trayClickCount == 2) {
      bool isVisible = await windowManager.isVisible();
      if (isVisible) {
        await windowManager.minimize();
        await windowManager.hide();

        return;
      }

      await windowManager.show();
      await windowManager.focus();

      trayClickCount = 0;
    }
  }

  // window functions
  @override
  void onWindowClose() async {
    bool _isPreventClose = await windowManager.isPreventClose();
    if (_isPreventClose) {
      showDialog(
        context: context,
        builder: (_) {
          return ContentDialog(
            title: const Text('Close or minimize to tray'),
            content: const Text(
                'Choose what you want: close the app or minimize it to tray'),
            actions: [
              Button(
                child: const Text('Minimize'),
                onPressed: () async {
                  Navigator.pop(context);
                  await windowManager.minimize();
                  await windowManager.hide();
                },
              ),
              Button(
                child: const Text('Close'),
                onPressed: () async {
                  Navigator.pop(context);
                  windowManager.destroy();
                },
              ),
              FilledButton(
                child: const Text('Cancel'),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ],
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return NavigationView(
      appBar: NavigationAppBar(
        // Why the fuck this is moving??
        automaticallyImplyLeading: false,
        leading: const Padding(
          padding: EdgeInsets.only(right: 8),
          child: SizedBox(
            height: 20,
            width: 20,
            child: Image(
              image: AssetImage('assets/images/lastfm discord smol.png'),
            ),
          ),
        ),
        title: const DragToMoveArea(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              appTitle,
            ),
          ),
        ),
        actions: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Expanded(
              child: DragToMoveArea(
                child: SizedBox(),
              ),
            ),
            WindowButtons()
          ],
        ),
      ),
      pane: NavigationPane(
        selected: index,
        onChanged: (i) => setState(() => index = i),
        size: const NavigationPaneSize(
          openMaxWidth: 250,
          openMinWidth: 200,
          headerHeight: 0,
        ),
        displayMode: PaneDisplayMode.open,
        indicator: const StickyNavigationIndicator(),
        items: [
          PaneItem(
            icon: const Icon(FluentIcons.settings),
            title: const Text('Last.fm settings'),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.preview_link),
            title: const Text('Discord Rich Presence'),
          ),
        ],
        footerItems: [
          PaneItemSeparator(),
          PaneItem(
            icon: const Icon(FluentIcons.info),
            title: const Text('About'),
          ),
        ],
      ),
      content: NavigationBody(
        index: index,
        children: const [
          SettingsPage(),
          DiscordRPCPage(),
          AboutPage(),
        ],
      ),
    );
  }
}
