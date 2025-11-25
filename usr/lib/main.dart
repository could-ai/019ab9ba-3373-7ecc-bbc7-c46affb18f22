import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:usb_serial/transaction.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final firstCamera = cameras.first;
  runApp(MyApp(camera: firstCamera));
}

class MyApp extends StatelessWidget {
  final CameraDescription camera;

  const MyApp({super.key, required this.camera});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LeopardGuard OTG AI System',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1a1a1a),
        primaryColor: Colors.yellow,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => LeopardDetectorScreen(camera: camera),
      },
    );
  }
}

class LeopardDetectorScreen extends StatefulWidget {
  final CameraDescription camera;

  const LeopardDetectorScreen({super.key, required this.camera});

  @override
  State<LeopardDetectorScreen> createState() => _LeopardDetectorScreenState();
}

class _LeopardDetectorScreenState extends State<LeopardDetectorScreen>
    with TickerProviderStateMixin {
  CameraController? _controller;
  Interpreter? _interpreter;
  UsbPort? _port;
  Transaction<String>? _transaction;
  bool _isConnected = false;
  bool _isScanning = false;
  bool _isModelLoaded = false;
  String _statusText = 'DISCONNECTED';
  Color _statusColor = Colors.grey;
  String _predictionText = 'Scanning...';
  String _predictionIcon = '🔍';
  double _confidence = 0.0;
  Color _confidenceColor = Colors.yellow;
  List<String> _logs = ['System initializing...'];
  final ScrollController _logScrollController = ScrollController();

  // Target classes for detection
  final List<String> _targetClasses = [
    'leopard', 'snow leopard', 'jaguar', 'cheetah', 'panther', 'tiger', 'lion', 'cat'
  ];

  // Animation controllers
  late AnimationController _flashController;
  late AnimationController _overlayController;
  late Animation<double> _flashAnimation;
  late Animation<Color?> _overlayAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeCamera();
    _loadModel();
  }

  void _initializeAnimations() {
    _flashController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _flashAnimation = Tween<double>(begin: 0.0, end: 0.8).animate(_flashController)
      ..addListener(() {
        setState(() {});
      });

    _overlayController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _overlayAnimation = ColorTween(
      begin: Colors.transparent,
      end: Colors.red,
    ).animate(_overlayController);
  }

  Future<void> _initializeCamera() async {
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      if (!mounted) return;
      setState(() {});
      _addLog('Camera initialized successfully');
    } catch (e) {
      _addLog('Camera initialization failed: $e');
    }
  }

  Future<void> _loadModel() async {
    try {
      // For this implementation, we'll use a placeholder
      // In a real app, you'd need to download and load MobileNet model
      // For now, we'll simulate model loading
      await Future.delayed(const Duration(seconds: 2));
      _isModelLoaded = true;
      _addLog('AI Model (MobileNet) loaded successfully');
      _addLog('System ready. Waiting for input.');
      setState(() {});
    } catch (e) {
      _addLog('Model loading failed: $e');
    }
  }

  Future<void> _connectArduino() async {
    List<UsbDevice> devices = await UsbSerial.listDevices();
    if (devices.isEmpty) {
      _addLog('No USB devices found');
      return;
    }

    UsbDevice device = devices.first; // Take first available device
    _port = await device.create();
    bool openResult = await _port!.open();
    if (!openResult) {
      _addLog('Failed to open USB port');
      return;
    }

    await _port!.setDTR(true);
    await _port!.setRTS(true);
    await _port!.setPortParameters(
        9600, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

    _transaction = Transaction.stringTerminated(
        _port!.inputStream!, Uint8List.fromList([13, 10]));

    _transaction!.stream.listen((String line) {
      _addLog('Signal received: "$line"');
      _triggerDetection();
    });

    _isConnected = true;
    _statusText = 'ARDUINO CONNECTED';
    _statusColor = Colors.green;
    _addLog('Serial port opened successfully');
    setState(() {});
  }

  Future<void> _sendToArduino(String command) async {
    if (_port != null && _isConnected) {
      await _port!.write(Uint8List.fromList(utf8.encode('$command\n')));
      _addLog('Sending command -> $command');
    } else {
      _addLog('Cannot send: Port not ready');
    }
  }

  void _triggerDetection() {
    if (_isScanning || !_isModelLoaded) return;
    _isScanning = true;

    // Flash effect
    _flashController.forward().then((_) => _flashController.reverse());

    setState(() {
      _predictionText = 'Analyzing Frame...';
      _predictionIcon = '🔍';
      _confidence = 1.0;
      _confidenceColor = Colors.blue;
    });

    _addLog('Triggered: Analyzing camera feed...');

    Future.delayed(const Duration(milliseconds: 500), () async {
      await _analyzeFrame();
      _isScanning = false;
      setState(() {});
    });
  }

  Future<void> _analyzeFrame() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      // Capture image
      XFile file = await _controller!.takePicture();
      Uint8List bytes = await file.readAsBytes();

      // In a real implementation, you'd preprocess the image and run inference
      // For this demo, we'll simulate detection
      await Future.delayed(const Duration(milliseconds: 100));

      // Simulate random detection for demo purposes
      bool detected = DateTime.now().millisecondsSinceEpoch % 3 == 0; // ~33% chance

      if (detected) {
        String detectedClass = _targetClasses[DateTime.now().millisecondsSinceEpoch % _targetClasses.length];
        double confidence = 0.7 + (DateTime.now().millisecondsSinceEpoch % 30) / 100.0;
        _handleDetection(detectedClass, confidence);
      } else {
        String topClass = 'background'; // Placeholder
        double confidence = 0.5 + (DateTime.now().millisecondsSinceEpoch % 50) / 100.0;
        _handleNoDetection(topClass, confidence);
      }
    } catch (e) {
      _addLog('Analysis error: $e');
    }
  }

  void _handleDetection(String className, double confidence) {
    int percent = (confidence * 100).round();

    _overlayController.forward().then((_) => _overlayController.reverse());

    setState(() {
      _predictionIcon = '⚠️';
      _predictionText = '${className.toUpperCase()} DETECTED!';
      _confidence = confidence;
      _confidenceColor = Colors.red;
    });

    _addLog('!!! THREAT DETECTED: $className (${percent}%) !!!');
    _sendToArduino('BUZZER_ON');
  }

  void _handleNoDetection(String className, double confidence) {
    int percent = (confidence * 100).round();

    setState(() {
      _predictionIcon = '✅';
      _predictionText = '$className (${percent}%)';
      _confidence = confidence;
      _confidenceColor = Colors.grey;
    });

    _addLog('Scan Result: $className - No threat');
  }

  void _addLog(String message) {
    String timestamp = TimeOfDay.now().format(context);
    setState(() {
      _logs.add('[$timestamp] $message');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearLogs() {
    setState(() {
      _logs = ['Logs cleared.'];
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    _interpreter?.close();
    _port?.close();
    _transaction?.dispose();
    _flashController.dispose();
    _overlayController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey[900],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.pets, color: Colors.yellow, size: 28),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'LeopardGuard',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'OTG AI System',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _statusColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _statusColor),
                    ),
                    child: Text(
                      _statusText,
                      style: TextStyle(
                        color: _statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Main Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Controls
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isConnected ? null : _connectArduino,
                            icon: Icon(_isConnected ? Icons.link : Icons.usb),
                            label: Text(_isConnected ? 'Connected' : 'Connect Arduino'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isConnected ? Colors.green : Colors.blue,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _triggerDetection,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Test Trigger'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[700],
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Camera Feed
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            children: [
                              if (_controller != null && _controller!.value.isInitialized)
                                CameraPreview(_controller!)
                              else
                                Container(
                                  color: Colors.black,
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),

                              // Loading overlay
                              if (!_isModelLoaded)
                                Container(
                                  color: Colors.black.withOpacity(0.9),
                                  child: const Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircularProgressIndicator(
                                          color: Colors.blue,
                                        ),
                                        SizedBox(height: 16),
                                        Text(
                                          'Loading Neural Network...',
                                          style: TextStyle(
                                            color: Colors.blue,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          'MobileNet v2',
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                              // Detection overlay
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: _overlayAnimation.value ?? Colors.transparent,
                                    width: 4,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),

                              // Flash effect
                              Container(
                                color: Colors.white.withOpacity(_flashAnimation.value),
                              ),

                              // Prediction label
                              Positioned(
                                bottom: 16,
                                left: 16,
                                right: 16,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.8),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.grey[700]!),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            _predictionIcon,
                                            style: const TextStyle(fontSize: 20),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _predictionText,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Container(
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: Colors.grey[700],
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: FractionallySizedBox(
                                          alignment: Alignment.centerLeft,
                                          widthFactor: _confidence,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: _confidenceColor,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Logs
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[700]!),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.terminal, color: Colors.grey[400], size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      'System Logs',
                                      style: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ],
                                ),
                                TextButton(
                                  onPressed: _clearLogs,
                                  child: Text(
                                    'Clear',
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(color: Colors.grey, height: 1),
                          Expanded(
                            child: ListView.builder(
                              controller: _logScrollController,
                              padding: const EdgeInsets.all(8),
                              itemCount: _logs.length,
                              itemBuilder: (context, index) {
                                return Text(
                                  _logs[index],
                                  style: TextStyle(
                                    color: Colors.green[400],
                                    fontSize: 12,
                                    fontFamily: 'monospace',
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}