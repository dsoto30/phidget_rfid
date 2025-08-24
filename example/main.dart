// example/main.dart
import 'package:phidget_rfid/phidget_rfid.dart';

void main() async {
  print('--- Phidget RFID Example ---');

  final rfidReader = PhidgetRFID();

  try {
    print('Initializing PhidgetRFID...');
    await rfidReader.initialize();
    print('Initialization successful. Waiting for events...');

    // Listen to the event stream
    final subscription = rfidReader.eventStream.listen((event) {
      switch (event) {
        case PhidgetAttachedEvent():
          print('Event: Device Attached!');
        case PhidgetDetachedEvent():
          print('Event: Device Detached!');
        case PhidgetTagScannedEvent():
          print('Event: Tag Scanned -> ${event.tag}');
        case PhidgetTagLostEvent():
          print('Event: Tag Lost -> ${event.tag}');
      }
    });

    print('\nScan an RFID tag or attach/detach the reader.');
    print('This example will automatically exit in 60 seconds.');

    // Keep the example running for a bit to receive events.
    await Future.delayed(const Duration(seconds: 60));

    // Clean up
    await subscription.cancel();
    rfidReader.dispose();
    print('\nExample finished.');
  } catch (e) {
    print('An error occurred: $e');
    print('\nIs the Phidgets driver installed and the device plugged in?');
  }
}
