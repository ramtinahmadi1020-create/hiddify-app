import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LicenseScreen extends StatefulWidget {
  final VoidCallback onActivated;
  const LicenseScreen({super.key, required this.onActivated});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final TextEditingController _controller = TextEditingController();
  String? _errorMessage;
  int _failedAttempts = 0;
  bool _isLocked = false;
  Duration? _remainingTime;

  // 🔑 رمز لایسنس دلخواه خودت رو اینجا بذار
  static const String _validKey = "RAMTIN-VPN-2026";

  @override
  void initState() {
    super.initState();
    _checkLockStatus();
  }

  Future<void> _checkLockStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final lockUntil = prefs.getInt('license_lock_until') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (lockUntil > now) {
      setState(() {
        _isLocked = true;
        _remainingTime = Duration(milliseconds: lockUntil - now);
      });
      _startCountdown();
    }
  }

  void _startCountdown() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted || _remainingTime == null) return;
      final newRemaining = _remainingTime! - const Duration(seconds: 1);
      if (newRemaining.inSeconds <= 0) {
        setState(() {
          _isLocked = false;
          _remainingTime = null;
          _failedAttempts = 0;
        });
      } else {
        setState(() {
          _remainingTime = newRemaining;
        });
        _startCountdown();
      }
    });
  }

  Future<void> _verifyLicense() async {
    final entered = _controller.text.trim();
    if (entered == _validKey) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('license_activated', true);
      widget.onActivated();
    } else {
      _failedAttempts++;
      if (_failedAttempts >= 3) {
        final prefs = await SharedPreferences.getInstance();
        final lockUntil = DateTime.now().add(const Duration(minutes: 15)).millisecondsSinceEpoch;
        await prefs.setInt('license_lock_until', lockUntil);
        setState(() {
          _isLocked = true;
          _remainingTime = const Duration(minutes: 15);
          _errorMessage = "Too many failed attempts.";
        });
        _startCountdown();
      } else {
        setState(() {
          _errorMessage = "Invalid license key. Attempts left: ${3 - _failedAttempts}";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 80, color: Theme.of(context).primaryColor),
              const SizedBox(height: 24),
              const Text("License Activation", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text("Please enter your license key to continue.", textAlign: TextAlign.center),
              const SizedBox(height: 24),
              if (_isLocked) ...[
                Text(
                  "Locked. Please wait: ${_remainingTime?.inMinutes ?? 0}:${((_remainingTime?.inSeconds ?? 0) % 60).toString().padLeft(2, '0')}",
                  style: const TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ] else ...[
                TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: 'License Key',
                    errorText: _errorMessage,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _verifyLicense,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: const Text("Activate", style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
