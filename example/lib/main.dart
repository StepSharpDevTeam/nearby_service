import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:nearby_service/nearby_service.dart';
import 'package:provider/provider.dart';

import 'components/app_snack_bar.dart';

part 'components/action_button.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final service = AppService();
  await service.getPlatformInfo();
  runApp(
    MyApp(service: service),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.service});

  final AppService service;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: service,
      child: MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.pink),
        ),
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Nearby service example app'),
          ),
          body: Consumer<AppService>(builder: (context, service, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Platform: ${service.platformVersion}\n'
                        'Model: ${service.platformModel}',
                      ),
                      if (service.currentDeviceInfo != null)
                        Text(
                          'Device Name: ${service.currentDeviceInfo!.displayName}'
                          '${Platform.isIOS ? '\nDevice ID: ${service.currentDeviceInfo!.id}' : ''}',
                        ),
                      if (Platform.isIOS)
                        Text(
                          'You are ${service.isIOSBrowser ? 'going to find your friend' : 'waiting for another user to connect'}',
                        ),
                      Text(
                        'Communication channel state: ${service.communicationChannelState.previewName}',
                      )
                    ],
                  ),
                ),
                Flexible(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeLeft: true,
                    child: Stepper(
                      controlsBuilder: (context, _) => const SizedBox.shrink(),
                      currentStep: service.state.step,
                      steps: [
                        ...AppState.steps.map((e) {
                          return Step(
                            title: Text(
                              e.title,
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle:
                                e.subtitle != null ? Text(e.subtitle!) : null,
                            content: e.content,
                            isActive: e == service.state,
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

///
/// DOMAIN LEVEL
///

enum AppState {
  idle(title: "Let's start!"),
  permissions(title: "Provide permissions"),
  checkServices(title: "Check services"),
  selectClientType(
    title: 'Do you want to find your friend from this device?',
    subtitle:
        'Click "Yes" if you will search, click "No" if you will wait for your friend to connect',
  ),
  readyToDiscover(title: "Ready to discover!"),
  discoveringPeers(title: "Discovering devices..."),
  streamingPeers(title: "Peers stream got!"),
  loadingConnection(title: "Loading your connection"),
  connected(title: "Connected!"),
  communicationChannelCreated(title: "You can communicate!");

  static final List<AppState> androidSteps = [
    AppState.idle,
    AppState.permissions,
    AppState.checkServices,
    AppState.readyToDiscover,
    AppState.discoveringPeers,
    AppState.streamingPeers,
    AppState.loadingConnection,
    AppState.connected,
    AppState.communicationChannelCreated,
  ];
  static final List<AppState> iosSteps = [
    AppState.idle,
    AppState.selectClientType,
    AppState.readyToDiscover,
    AppState.discoveringPeers,
    AppState.streamingPeers,
    AppState.loadingConnection,
    AppState.connected,
    AppState.communicationChannelCreated,
  ];

  static final List<AppState> steps = [
    if (Platform.isAndroid) ...androidSteps,
    if (Platform.isIOS) ...iosSteps,
  ];

  const AppState({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  Widget get content {
    return switch (this) {
      (AppState.idle) => const _IdleBody(),
      (AppState.permissions) => const _PermissionsBody(),
      (AppState.checkServices) => const _CheckServiceBody(),
      (AppState.selectClientType) => const _SelectClientTypeBody(),
      (AppState.readyToDiscover) => const _ReadyBody(),
      (AppState.discoveringPeers) => const _DiscoveringBody(),
      (AppState.streamingPeers) => const _StreamingState(),
      (AppState.loadingConnection) =>
        const Center(child: CircularProgressIndicator.adaptive()),
      (AppState.connected) => const _ConnectedBody(),
      (AppState.communicationChannelCreated) => const _ConnectedSocketBody(),
    };
  }

  int get step {
    return steps.indexOf(this);
  }
}

extension on CommunicationChannelState {
  String get previewName {
    return switch (this) {
      CommunicationChannelState.notConnected => 'Not connected',
      CommunicationChannelState.loading => 'Connecting',
      CommunicationChannelState.connected => 'Connected',
    };
  }
}

class AppService extends ChangeNotifier {
  late final _nearbyService = NearbyService.getInstance()
    ..communicationChannelState.addListener(notifyListeners);

  AppState state = AppState.idle;
  List<NearbyDevice>? peers;
  NearbyDevice? connectedDevice;
  NearbyDeviceInfo? currentDeviceInfo;

  String platformVersion = 'Unknown';
  String platformModel = 'Unknown';

  StreamSubscription? peersSubscription;
  StreamSubscription? connectedDeviceSubscription;

  @override
  void dispose() {
    stopListeningAll();
    super.dispose();
  }

  CommunicationChannelState get communicationChannelState {
    return _nearbyService.communicationChannelState.value;
  }

  bool get isIOSBrowser {
    return _nearbyService.ios?.isBrowser.value ?? false;
  }

  bool get isAndroidGroupOwner {
    return Platform.isAndroid &&
        (_nearbyService.android?.connectionInfo?.isGroupOwner ?? false);
  }

  Future<void> getPlatformInfo() async {
    platformVersion = await _nearbyService.getPlatformVersion() ?? 'Unknown';
    platformModel = await _nearbyService.getPlatformModel() ?? 'Unknown';
    notifyListeners();
  }

  Future<String> getSavedIOSDeviceName() async {
    return (await _nearbyService.ios?.getSavedDeviceName()) ?? platformModel;
  }

  Future<void> initialize(String? iosDeviceName) async {
    try {
      await _nearbyService.initialize(
        data: NearbyInitializeData(iosDeviceName: iosDeviceName),
      );
      currentDeviceInfo = await _nearbyService.getCurrentDeviceInfo();
      updateState(
        Platform.isAndroid ? AppState.permissions : AppState.selectClientType,
      );
    } catch (e, s) {
      if (kDebugMode) {
        print(e);
        print(s);
      }
    } finally {
      notifyListeners();
    }
  }

  Future<void> requestPermissions() async {
    try {
      final result = await _nearbyService.android?.requestPermissions();
      if (result ?? false) {
        updateState(AppState.checkServices);
      }
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }
  }

  Future<bool> checkWifiService() async {
    final result = await _nearbyService.android?.checkWifiService();
    if (result ?? false) {
      updateState(AppState.readyToDiscover);
      return true;
    }
    return false;
  }

  Future<void> openServicesSettings() async {
    await _nearbyService.openServicesSettings();
  }

  void setIsBrowser({required bool value}) {
    _nearbyService.ios?.setIsBrowser(value: value);
    updateState(AppState.readyToDiscover);
  }

  Future<void> discover() async {
    try {
      final result = await _nearbyService.discover();
      if (result) {
        updateState(AppState.discoveringPeers);
      }
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }
  }

  Future<void> stopDiscovery() async {
    try {
      final result = await _nearbyService.stopDiscovery();
      if (result) {
        updateState(AppState.readyToDiscover);
      }
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }
  }

  Future<void> startListeningPeers() async {
    try {
      peersSubscription = _nearbyService.getPeersStream().listen(
        (event) {
          peers = event;
          notifyListeners();
        },
      );
      updateState(AppState.streamingPeers);
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }
  }

  Future<void> stopListeningPeers() async {
    peersSubscription?.cancel();
    peers = null;
    updateState(AppState.discoveringPeers);
  }

  Future<void> connect(NearbyDevice device) async {
    try {
      await _nearbyService.connect(device);
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    }
    notifyListeners();
  }

  Future<void> startListeningConnectedDevice(NearbyDevice device) async {
    updateState(AppState.loadingConnection);
    try {
      connectedDeviceSubscription =
          _nearbyService.getConnectedDeviceStream(device).listen(
        (event) async {
          final wasConnected = connectedDevice?.status.isConnected ?? false;
          final nowConnected = event?.status.isConnected ?? false;
          if (wasConnected && !nowConnected) {
            stopListeningAll();
            return;
          }
          connectedDevice = event;
          if (connectedDevice != null &&
              state != AppState.connected &&
              state != AppState.communicationChannelCreated) {
            updateState(AppState.connected);
          }
          notifyListeners();
        },
      );
    } catch (e) {
      updateState(AppState.streamingPeers, shouldNotify: false);
    }
    notifyListeners();
  }

  Future<void> stopListeningConnectedDevice() async {
    await connectedDeviceSubscription?.cancel();
    await _nearbyService.endCommunicationChannel();
    connectedDeviceSubscription = null;
    connectedDevice = null;

    notifyListeners();
  }

  Future<void> startCommunicationChannel({
    ValueChanged<ReceivedNearbyMessage>? listener,
  }) async {
    final eventListener = NearbyServiceStreamListener(
      onCreated: (_) {
        updateState(AppState.communicationChannelCreated);
      },
      onData: (event) {
        listener?.call(event);
      },
      onError: (e, [StackTrace? s]) {
        stopListeningAll();
      },
    );

    await _nearbyService.startCommunicationChannel(
      NearbyCommunicationChannelData(
        connectedDevice!.info.id,
        eventListener: eventListener,
      ),
    );
  }

  void send(String message) {
    if (connectedDevice == null) return;
    _nearbyService.send(
      OutgoingNearbyMessage(
        value: message,
        receiver: connectedDevice!.info,
      ),
    );
  }

  Future<void> disconnect(NearbyDevice device) async {
    try {
      await _nearbyService.disconnect(device);
    } catch (e) {
      if (kDebugMode) {
        print(e);
      }
    } finally {
      await stopListeningAll();
    }
    notifyListeners();
  }

  Future<void> stopListeningAll() async {
    await stopListeningConnectedDevice();
    await stopListeningPeers();
    await stopDiscovery();
  }

  void updateState(AppState state, {bool shouldNotify = true}) {
    this.state = state;
    if (shouldNotify) {
      notifyListeners();
    }
  }
}

///
/// APP STATES
///
///

class _IdleBody extends StatefulWidget {
  const _IdleBody();

  @override
  State<_IdleBody> createState() => _IdleBodyState();
}

class _IdleBodyState extends State<_IdleBody> {
  late final controller = TextEditingController();
  bool initialized = false;

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      context.read<AppService>().getSavedIOSDeviceName().then((value) {
        controller.text = value;
        controller.selection = TextSelection.collapsed(offset: value.length);
        setState(() {
          initialized = true;
        });
      });
    });
    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!initialized) {
      return const Center(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Getting saved name...',
              style: TextStyle(fontSize: 12),
            ),
            SizedBox(height: 10),
            CircularProgressIndicator.adaptive(),
          ],
        ),
      );
    }
    return Center(
      child: Column(
        children: [
          if (Platform.isIOS)
            Padding(
              padding: const EdgeInsets.only(bottom: 10.0),
              child: TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Device Name',
                  hintText: 'Enter the name of your device',
                ),
                controller: controller,
              ),
            ),
          _ActionButton(
            onTap: () {
              context.read<AppService>().initialize(controller.text);
            },
            title: 'Tap to start',
          ),
        ],
      ),
    );
  }
}

class _PermissionsBody extends StatelessWidget {
  const _PermissionsBody();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppService>(builder: (context, service, _) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ActionButton(
            onTap: service.requestPermissions,
            title: 'Request permissions',
          ),
        ],
      );
    });
  }
}

class _CheckServiceBody extends StatefulWidget {
  const _CheckServiceBody();

  @override
  State<_CheckServiceBody> createState() => _CheckServiceBodyState();
}

class _CheckServiceBodyState extends State<_CheckServiceBody> {
  bool showEnableButton = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActionButton(
          onTap: () {
            context.read<AppService>().checkWifiService().then((value) {
              if (!value) {
                setState(() {
                  showEnableButton = true;
                });
                AppShackBar.show(context, 'Please enable Wi-fi');
              }
            });
          },
          title: 'Check Wi-fi service',
        ),
        if (showEnableButton)
          Padding(
            padding: const EdgeInsets.only(top: 10.0),
            child: _ActionButton(
              onTap: context.read<AppService>().openServicesSettings,
              title: 'Open settings',
            ),
          ),
      ],
    );
  }
}

class _SelectClientTypeBody extends StatelessWidget {
  const _SelectClientTypeBody();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ActionButton(
          title: 'Yes',
          onTap: () {
            context.read<AppService>().setIsBrowser(value: true);
          },
        ),
        const SizedBox(width: 10),
        _ActionButton(
          title: 'No',
          onTap: () {
            context.read<AppService>().setIsBrowser(value: false);
          },
        ),
      ],
    );
  }
}

class _ReadyBody extends StatelessWidget {
  const _ReadyBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActionButton(
          onTap: context.read<AppService>().discover,
          title: 'Start discover peers',
        ),
        const SizedBox(height: 10),
        if (Platform.isIOS)
          _ActionButton(
            onTap: () {
              context.read<AppService>().updateState(AppState.selectClientType);
            },
            title: 'Reselect client type',
            type: _ActionButtonType.warning,
          ),
      ],
    );
  }
}

class _DiscoveringBody extends StatelessWidget {
  const _DiscoveringBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActionButton(
          type: _ActionButtonType.warning,
          onTap: context.read<AppService>().stopDiscovery,
          title: 'Stop discovery',
        ),
        const SizedBox(height: 10),
        _ActionButton(
          onTap: context.read<AppService>().startListeningPeers,
          title: 'Now it is discovering. Tap to get peers!',
        )
      ],
    );
  }
}

class _StreamingState extends StatelessWidget {
  const _StreamingState();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ActionButton(
          type: _ActionButtonType.warning,
          onTap: context.read<AppService>().stopListeningPeers,
          title: 'Stop stream peers',
        ),
        const SizedBox(height: 10),
        const _PeersBody(),
      ],
    );
  }
}

class _PeersBody extends StatelessWidget {
  const _PeersBody();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppService>(
      builder: (context, service, _) {
        return (service.peers != null && service.peers!.isNotEmpty)
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...service.peers!.map(
                    (e) {
                      return Container(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: _DevicePreview(device: e),
                      );
                    },
                  ),
                ],
              )
            : Text(
                Platform.isAndroid || service.isIOSBrowser
                    ? 'No one here ('
                    : "Wait until someone invites you!",
                textAlign: TextAlign.center,
              );
      },
    );
  }
}

class _ConnectedBody extends StatelessWidget {
  const _ConnectedBody();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppService>(
      builder: (context, service, _) {
        final device = service.connectedDevice;
        return device != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!device.status.isConnected)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text('Connection lost'),
                        ),
                      )
                    else if (!device.status.isConnected)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Connection lost'),
                          _ActionButton(
                            onTap: () {
                              service.connect(device);
                            },
                            title: 'Reconnect',
                          ),
                        ],
                      )
                    else
                      _DevicePreview(device: device, largeView: true),
                    const SizedBox(height: 10),
                    if (service.communicationChannelState !=
                        CommunicationChannelState.loading)
                      _ActionButton(
                        onTap: () => service.startCommunicationChannel(
                          listener: (event) => AppShackBar.show(
                            Scaffold.of(context).context,
                            event.value,
                            subtitle: 'From ${event.sender.displayName} '
                                '(ID: ${event.sender.id})',
                          ),
                        ),
                        title: 'Start communicate',
                      )
                    else
                      Text(
                        'Connecting socket.. '
                        '${service.isAndroidGroupOwner ? "Waiting a client for connect" : "Waiting a connection"}',
                      )
                  ],
                ),
              )
            : const SizedBox();
      },
    );
  }
}

class _ConnectedSocketBody extends StatefulWidget {
  const _ConnectedSocketBody();

  @override
  State<_ConnectedSocketBody> createState() => _ConnectedSocketBodyState();
}

class _ConnectedSocketBodyState extends State<_ConnectedSocketBody> {
  String message = '';

  @override
  Widget build(BuildContext context) {
    return Consumer<AppService>(
      builder: (context, service, _) {
        final device = service.connectedDevice;
        if (device == null) {
          return Center(
            child: _ActionButton(
              onTap: service.stopListeningAll,
              title: 'Restart',
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DevicePreview(device: device, largeView: true),
            const SizedBox(height: 10),
            Flexible(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (value) => setState(() {
                        message = value;
                      }),
                      decoration: const InputDecoration(
                        enabledBorder: OutlineInputBorder(),
                        border: OutlineInputBorder(),
                        focusedBorder: OutlineInputBorder(),
                        hintText: 'Enter your message',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _ActionButton(
                    title: 'Send',
                    onTap: () {
                      service.send(message);
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DevicePreview extends StatelessWidget {
  const _DevicePreview({required this.device, this.largeView = false});

  final NearbyDevice device;
  final bool largeView;

  @override
  Widget build(BuildContext context) {
    final color = device.status.isConnected
        ? Colors.greenAccent.shade700
        : Colors.blueGrey;

    final avatar = CircleAvatar(
      backgroundColor: Colors.pink.shade800,
      foregroundColor: Colors.white,
      maxRadius: largeView ? 100 : 30,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(
          device.info.displayName
              .split(' ')
              .map((e) => e.substring(0, 1).toUpperCase())
              .join(''),
          style: TextStyle(fontSize: largeView ? 32 : 16),
        ),
      ),
    );
    final name = Text(
      '${device.info.displayName} '
      '${device.byPlatform(onAndroid: (d) => d.isGroupOwner ? " - group owner" : "") ?? ''}',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
    );
    final id = Text(
      'ID: ${device.info.id}',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 10,
          ),
    );
    final status = Text(
      device.byPlatform(
            onAny: (d) => d.status.name,
            onIOS: (d) =>
                context.select<AppService, bool>((v) => v.isIOSBrowser)
                    ? "Peer found | ${d.status.name}"
                    : "Pending invitation | ${d.status.name}",
          ) ??
          '',
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
          ),
    );

    final disconnectButton = device.status.isConnected
        ? TextButton(
            onPressed: () => context.read<AppService>().disconnect(device),
            child: const Text('Disconnect'),
          )
        : null;
    if (largeView) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          avatar,
          const SizedBox(height: 10),
          name,
          const SizedBox(height: 5),
          id,
          if (disconnectButton != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: disconnectButton,
            ),
        ],
      );
    } else {
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (!device.status.isConnected) {
            context.read<AppService>().connect(device);
          } else {
            context.read<AppService>().startListeningConnectedDevice(device);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                flex: 3,
                child: Row(
                  children: [
                    avatar,
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [name, id, status],
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: Text(
                  device.status.isConnected ? 'Tap to chat' : 'Tap to connect',
                  style: TextStyle(
                      color: Colors.greenAccent.shade700, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              )
            ],
          ),
        ),
      );
    }
  }
}
