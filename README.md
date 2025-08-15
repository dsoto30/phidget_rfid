# Phidget RFID Reader

A Flutter package for interacting with a Phidget RFID reader on Windows, Linux, and macOS. This package uses FFI to communicate with the native `phidget22` library, allowing you to easily integrate Phidget RFID readers into your Flutter applications.

## Features

-   **Cross-Platform:** Works on Windows, Linux, and macOS.
-   **Event-Driven:** Provides a stream of events for device attachment, detachment, and tag scanning.
-   **Simple API:** Easy to initialize the device and listen for events.

## Prerequisites

You must have the Phidget22 library installed on your system. You can find the installation instructions for your operating system on the [Phidgets website](https://www.phidgets.com/docs/Operating_System_Support).

## Installation

Add the following to your `pubspec.yaml` file:

```yaml
dependencies:
  phidget_rfid: ^1.0.0
```

Then, run `flutter pub get`.

## Usage

Here is a simple example of how to use the `phidget_rfid` package in a Flutter application. This example also shows how to enable logging to see detailed output from the PhidgetRFID class.

First, add the `logging` package to your `pubspec.yaml`:

```yaml
dependencies:
  phidget_rfid: ^1.0.0
  logging: ^1.2.0 # Or the latest version
```

Then, you can use the following code in your application:

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:phidget_rfid/phidget_rfid.dart';
import 'package:logging/logging.dart';

void main() {
  // Enable logging to see the output from the PhidgetRFID class
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Phidget RFID Reader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Phidget RFID Reader Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late PhidgetRFID _phidgetService;
  StreamSubscription<PhidgetEvent>? _eventSubscription;

  String _status = 'Disconnected';
  String _lastTag = 'N/A';

  @override
  void initState() {
    super.initState();
    _phidgetService = PhidgetRFID();
    _connectPhidget();
  }

  void _connectPhidget() async {
    setState(() {
      _status = 'Initializing...';
      _lastTag = 'N/A';
    });

    try {
      await _phidgetService.initialize();

      _eventSubscription = _phidgetService.eventStream.listen((event) {
        if (!mounted) return;
        setState(() {
          switch (event) {
            case PhidgetAttachedEvent():
              _status = 'Connected';

            case PhidgetDetachedEvent():
              _status = 'Disconnected';
              _lastTag = 'N/A';

            case PhidgetTagScannedEvent():
              _status = 'Connected';
              _lastTag = event.tag;

            // --- THIS CASE IS UPDATED ---
            case PhidgetTagLostEvent():
              // When a tag is lost, revert to the connected state and clear the tag.
              _status = 'Connected';
              _lastTag = 'N/A';

            default:
              _status = 'Unknown Event';
              print(
                'Warning: Unhandled PhidgetEvent of type '{$event.runtimeType}' received.',
              );
          }
        });
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Error: ${e.toString()}';
      });
    }
  }

  void _disconnectPhidget() {
    _eventSubscription?.cancel();
    _phidgetService.dispose();

    _phidgetService = PhidgetRFID();

    setState(() {
      _status = 'Disconnected';
      _lastTag = 'N/A';
    });
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _phidgetService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isConnected = _status == 'Connected';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'Status: $_status',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            Text(
              'Last Tag Scanned:', // Label is now simplified
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              _lastTag,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: isConnected ? null : _connectPhidget,
                  child: const Text('Connect'),
                ),
                ElevatedButton(
                  onPressed:
                      _status != 'Disconnected' ? _disconnectPhidget : null,
                  child: const Text('Disconnect'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

## API

### `PhidgetRFID`

The main class for interacting with the Phidget RFID reader.

#### `PhidgetRFID()`

Creates an instance of the PhidgetRFID service and loads the native `phidget22` library.

#### `Future<void> initialize()`

Initializes the connection to the Phidget RFID reader and starts listening for events. Throws an exception if the device cannot be found or opened.

#### `Stream<PhidgetEvent> get eventStream`

A stream of `PhidgetEvent`s from the RFID reader.

#### `void dispose()`

Closes the connection to the RFID reader and releases all native resources.

### `PhidgetEvent`

A sealed class for all Phidget events.

-   `PhidgetAttachedEvent`: Fired when the Phidget RFID reader is attached.
-   `PhidgetDetachedEvent`: Fired when the Phidget RFID reader is detached.
-   `PhidgetTagScannedEvent`: Fired when an RFID tag is scanned. Contains the `tag` string.
-   `PhidgetTagLostEvent`: Fired when a previously scanned RFID tag is lost. Contains the `tag` string.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
