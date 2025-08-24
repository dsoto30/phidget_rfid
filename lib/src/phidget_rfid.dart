import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:logging/logging.dart'; // Import the logging package
import 'dart:typed_data';
import 'dart:convert';

// --- Define Event Classes for the Stream ---

/// Sealed base class for all Phidget events.
///
/// This class is extended by specific event types to provide detailed information
/// about each event from the Phidget RFID reader.
sealed class PhidgetEvent {}

/// Event fired when the Phidget RFID reader is attached.
///
/// This event indicates that the device has been successfully connected and is
/// ready to communicate.
class PhidgetAttachedEvent extends PhidgetEvent {
  /// Creates an instance of an attached event.
}

/// Event fired when the Phidget RFID reader is detached.
///
/// This event signals that the device has been disconnected from the system.
class PhidgetDetachedEvent extends PhidgetEvent {
  /// Creates an instance of a detached event.
}

/// Event fired when an RFID tag is scanned.
///
/// Contains the [tag] string that was read from the RFID tag.
class PhidgetTagScannedEvent extends PhidgetEvent {
  /// The tag identifier string read from the RFID tag.
  final String tag;

  /// Creates a new instance of a tag scanned event.
  PhidgetTagScannedEvent(this.tag);
}

/// Event fired when a previously scanned RFID tag is lost.
///
/// This event indicates that the RFID tag is no longer in the reader's field.
/// Contains the [tag] string that was lost.
class PhidgetTagLostEvent extends PhidgetEvent {
  /// The tag identifier string of the lost RFID tag.
  final String tag;

  /// Creates a new instance of a tag lost event.
  PhidgetTagLostEvent(this.tag);
}

// --- FFI Typedefs ---

/// A handle to a Phidget device.
typedef PhidgetHandle = IntPtr;

/// A return code from a Phidget API call.
typedef PhidgetReturnCode = Int32;

// Create, Open, Close, Delete
typedef _PhidgetRfidCreateC =
    PhidgetReturnCode Function(Pointer<PhidgetHandle>);
typedef _PhidgetRfidCreateDart = int Function(Pointer<PhidgetHandle>);
typedef _PhidgetOpenWaitForAttachmentC =
    PhidgetReturnCode Function(PhidgetHandle, Uint32);
typedef _PhidgetOpenWaitForAttachmentDart = int Function(int, int);
typedef _PhidgetCloseC = PhidgetReturnCode Function(PhidgetHandle);
typedef _PhidgetCloseDart = int Function(int);
typedef _PhidgetDeleteC = PhidgetReturnCode Function(Pointer<PhidgetHandle>);
typedef _PhidgetDeleteDart = int Function(Pointer<PhidgetHandle>);

// --- Callback Typedefs for Events ---
typedef _PhidgetRfidOnTagC =
    Void Function(PhidgetHandle, Pointer<Void>, Pointer<Utf8>, Int32);
typedef _PhidgetOnAttachC = Void Function(PhidgetHandle, Pointer<Void>);
typedef _PhidgetOnDetachC = Void Function(PhidgetHandle, Pointer<Void>);
typedef _PhidgetRfidOnTagLostC =
    Void Function(PhidgetHandle, Pointer<Void>, Pointer<Utf8>, Int32);

// --- Handler Setter Typedefs ---
typedef _PhidgetRfidSetOnTagHandlerC =
    PhidgetReturnCode Function(
      PhidgetHandle,
      Pointer<NativeFunction<_PhidgetRfidOnTagC>>,
      Pointer<Void>,
    );
typedef _PhidgetRfidSetOnTagHandlerDart =
    int Function(
      int,
      Pointer<NativeFunction<_PhidgetRfidOnTagC>>,
      Pointer<Void>,
    );
typedef _PhidgetSetOnAttachHandlerC =
    PhidgetReturnCode Function(
      PhidgetHandle,
      Pointer<NativeFunction<_PhidgetOnAttachC>>,
      Pointer<Void>,
    );
typedef _PhidgetSetOnAttachHandlerDart =
    int Function(
      int,
      Pointer<NativeFunction<_PhidgetOnAttachC>>,
      Pointer<Void>,
    );
typedef _PhidgetSetOnDetachHandlerC =
    PhidgetReturnCode Function(
      PhidgetHandle,
      Pointer<NativeFunction<_PhidgetOnDetachC>>,
      Pointer<Void>,
    );
typedef _PhidgetSetOnDetachHandlerDart =
    int Function(
      int,
      Pointer<NativeFunction<_PhidgetOnDetachC>>,
      Pointer<Void>,
    );
typedef _PhidgetRfidSetOnTagLostHandlerC =
    PhidgetReturnCode Function(
      PhidgetHandle,
      Pointer<NativeFunction<_PhidgetRfidOnTagLostC>>,
      Pointer<Void>,
    );
typedef _PhidgetRfidSetOnTagLostHandlerDart =
    int Function(
      int,
      Pointer<NativeFunction<_PhidgetRfidOnTagLostC>>,
      Pointer<Void>,
    );

/// A cross-platform class for interacting with a Phidget RFID reader.
///
/// This class handles loading the native Phidgets library, initializing the
/// device, and streaming events like attaching, detaching, and scanning tags.
class PhidgetRFID {
  final _log = Logger('PhidgetRFID'); // Create a logger instance

  late final DynamicLibrary _phidgetLibrary;
  late final _PhidgetRfidCreateDart _phidgetRfidCreate;
  late final _PhidgetOpenWaitForAttachmentDart _phidgetOpenWaitForAttachment;
  late final _PhidgetCloseDart _phidgetClose;
  late final _PhidgetDeleteDart _phidgetDelete;
  late final _PhidgetRfidSetOnTagHandlerDart _phidgetRfidSetOnTagHandler;
  late final _PhidgetSetOnAttachHandlerDart _phidgetSetOnAttachHandler;
  late final _PhidgetSetOnDetachHandlerDart _phidgetSetOnDetachHandler;
  late final _PhidgetRfidSetOnTagLostHandlerDart
  _phidgetRfidSetOnTagLostHandler;

  int _rfidHandle = 0;

  final StreamController<PhidgetEvent> _eventStreamController =
      StreamController<PhidgetEvent>.broadcast();

  NativeCallable<_PhidgetRfidOnTagC>? _onTagCallable;
  NativeCallable<_PhidgetOnAttachC>? _onAttachCallable;
  NativeCallable<_PhidgetOnDetachC>? _onDetachCallable;
  NativeCallable<_PhidgetRfidOnTagLostC>? _onTagLostCallable;

  /// A stream of [PhidgetEvent]s from the RFID reader.
  ///
  /// Listen to this stream to receive events such as [PhidgetAttachedEvent],
  /// [PhidgetDetachedEvent], [PhidgetTagScannedEvent], and [PhidgetTagLostEvent].
  Stream<PhidgetEvent> get eventStream => _eventStreamController.stream;

  /// Creates an instance of the PhidgetRFID service.
  ///
  /// This loads the native phidget22 library based on the current operating system.
  /// It supports Windows, Linux, and macOS.
  ///
  /// Throws an [Exception] if the operating system is not supported.
  PhidgetRFID() {
    String libraryPath;

    if (Platform.isWindows) {
      libraryPath = 'phidget22.dll';
    } else if (Platform.isMacOS) {
      // First, check the standard Framework installation path.
      // This will work for 99% of users out of the box.
      const defaultPath = '/Library/Frameworks/Phidget22.framework/Phidget22';

      if (File(defaultPath).existsSync()) {
        libraryPath = defaultPath;
      } else {
        // As a fallback, use a generic name. The README will instruct
        // users with non-standard installs on how to create a symbolic
        // link to make this path work.
        libraryPath = 'libphidget22.dylib';
      }
    } else {
      throw Exception(
        'Unsupported platform. This package currently supports Windows and macOS.',
      );
    }

    try {
      _phidgetLibrary = DynamicLibrary.open(libraryPath);
    } catch (e) {
      _log.severe(
        'FATAL: Could not load the Phidget22 library.\n'
        '1. Ensure the Phidgets driver is installed.\n'
        '2. On macOS, make sure you have run the `install_name_tool` command from the README.',
        e,
      );
      rethrow; // Rethrow the exception to halt execution.
    }

    // Load function pointers from the native library
    _phidgetRfidCreate = _phidgetLibrary
        .lookupFunction<_PhidgetRfidCreateC, _PhidgetRfidCreateDart>(
          'PhidgetRFID_create',
        );
    _phidgetOpenWaitForAttachment = _phidgetLibrary.lookupFunction<
      _PhidgetOpenWaitForAttachmentC,
      _PhidgetOpenWaitForAttachmentDart
    >('Phidget_openWaitForAttachment');
    _phidgetClose = _phidgetLibrary
        .lookupFunction<_PhidgetCloseC, _PhidgetCloseDart>('Phidget_close');
    _phidgetDelete = _phidgetLibrary
        .lookupFunction<_PhidgetDeleteC, _PhidgetDeleteDart>('Phidget_delete');
    _phidgetRfidSetOnTagHandler = _phidgetLibrary.lookupFunction<
      _PhidgetRfidSetOnTagHandlerC,
      _PhidgetRfidSetOnTagHandlerDart
    >('PhidgetRFID_setOnTagHandler');
    _phidgetSetOnAttachHandler = _phidgetLibrary.lookupFunction<
      _PhidgetSetOnAttachHandlerC,
      _PhidgetSetOnAttachHandlerDart
    >('Phidget_setOnAttachHandler');
    _phidgetSetOnDetachHandler = _phidgetLibrary.lookupFunction<
      _PhidgetSetOnDetachHandlerC,
      _PhidgetSetOnDetachHandlerDart
    >('Phidget_setOnDetachHandler');
    _phidgetRfidSetOnTagLostHandler = _phidgetLibrary.lookupFunction<
      _PhidgetRfidSetOnTagLostHandlerC,
      _PhidgetRfidSetOnTagLostHandlerDart
    >('PhidgetRFID_setOnTagLostHandler');
  }

  // --- Dart Callback Functions ---

  /// Callback function for when a tag is scanned.
  void _onTagCallback(
    int handle,
    Pointer<Void> ctx,
    Pointer<Utf8> tag,
    int protocol,
  ) {
    try {
      final Pointer<Uint8> bytePointer = tag.cast<Uint8>();

      int length = 0;
      while (bytePointer[length] != 0) {
        length++;
      }

      if (length == 0) return;

      final Uint8List tagBytes = bytePointer.asTypedList(length);

      // Decode the bytes into a string, replacing any malformed sequences.
      final tagString = utf8.decode(tagBytes, allowMalformed: true);

      _log.info('Tag Scanned: $tagString');
      if (!_eventStreamController.isClosed) {
        _eventStreamController.add(PhidgetTagScannedEvent(tagString));
      }
    } catch (e, stackTrace) {
      _log.severe('Error processing tag callback', e, stackTrace);
    }
  }

  /// Callback function for when the device is attached.
  void _onAttachCallback(int handle, Pointer<Void> ctx) {
    _log.info('Device Attached');
    if (!_eventStreamController.isClosed) {
      _eventStreamController.add(PhidgetAttachedEvent());
    }
  }

  /// Callback function for when the device is detached.
  void _onDetachCallback(int handle, Pointer<Void> ctx) {
    _log.info('Device Detached');
    if (!_eventStreamController.isClosed) {
      _eventStreamController.add(PhidgetDetachedEvent());
    }
  }

  /// Callback function for when a tag is lost.
  void _onTagLostCallback(
    int handle,
    Pointer<Void> ctx,
    Pointer<Utf8> tag,
    int protocol,
  ) {
    try {
      final Pointer<Uint8> bytePointer = tag.cast<Uint8>();

      int length = 0;
      while (bytePointer[length] != 0) {
        length++;
      }

      if (length == 0) return;

      final Uint8List tagBytes = bytePointer.asTypedList(length);

      // Decode the bytes into a string, replacing any malformed sequences.
      final tagString = utf8.decode(tagBytes, allowMalformed: true);

      _log.info('Tag Lost: $tagString');
      if (!_eventStreamController.isClosed) {
        _eventStreamController.add(PhidgetTagLostEvent(tagString));
      }
    } catch (e, stackTrace) {
      _log.severe('Error processing tag lost callback', e, stackTrace);
    }
  }

  /// Initializes the connection to the Phidget RFID reader and starts listening for events.
  ///
  /// This method creates a new RFID handle, sets up the event handlers, and
  /// waits for the device to be attached.
  ///
  /// Throws an [Exception] if the device cannot be found or opened.
  Future<void> initialize() async {
    final rfidPtr = calloc<PhidgetHandle>();
    try {
      var result = _phidgetRfidCreate(rfidPtr);
      if (result != 0) {
        throw Exception('Failed to create RFID handle. Error: $result');
      }

      _rfidHandle = rfidPtr.value;

      // --- Create NativeCallables and set handlers ---
      _onTagCallable = NativeCallable<_PhidgetRfidOnTagC>.listener(
        _onTagCallback,
      );
      _phidgetRfidSetOnTagHandler(
        _rfidHandle,
        _onTagCallable!.nativeFunction,
        nullptr,
      );

      _onAttachCallable = NativeCallable<_PhidgetOnAttachC>.listener(
        _onAttachCallback,
      );
      _phidgetSetOnAttachHandler(
        _rfidHandle,
        _onAttachCallable!.nativeFunction,
        nullptr,
      );

      _onDetachCallable = NativeCallable<_PhidgetOnDetachC>.listener(
        _onDetachCallback,
      );
      _phidgetSetOnDetachHandler(
        _rfidHandle,
        _onDetachCallable!.nativeFunction,
        nullptr,
      );

      _onTagLostCallable = NativeCallable<_PhidgetRfidOnTagLostC>.listener(
        _onTagLostCallback,
      );
      _phidgetRfidSetOnTagLostHandler(
        _rfidHandle,
        _onTagLostCallable!.nativeFunction,
        nullptr,
      );

      // --- Open the device ---
      result = _phidgetOpenWaitForAttachment(_rfidHandle, 5000);
      if (result != 0) {
        throw Exception(
          'Failed to open RFID reader. Make sure it is plugged in. Error: $result',
        );
      }
    } catch (e, stackTrace) {
      _log.severe('Error during initialization', e, stackTrace);
      dispose();
      rethrow;
    } finally {
      calloc.free(rfidPtr);
    }
  }

  /// Closes the connection to the RFID reader and releases all native resources.
  ///
  /// This method should be called when the application is finished with the
  /// Phidget device to ensure proper cleanup of handles and resources.
  void dispose() {
    if (_rfidHandle != 0) {
      _phidgetClose(_rfidHandle);
      final rfidPtr = calloc<PhidgetHandle>()..value = _rfidHandle;
      _phidgetDelete(rfidPtr);
      calloc.free(rfidPtr);
      _rfidHandle = 0;
    }

    _onTagCallable?.close();
    _onAttachCallable?.close();
    _onDetachCallable?.close();
    _onTagLostCallable?.close();

    if (!_eventStreamController.isClosed) {
      _eventStreamController.close();
    }
    _log.info('Phidget Service Disposed.');
  }
}
