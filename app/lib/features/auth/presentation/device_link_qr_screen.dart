import 'package:flutter/material.dart';
import '../../../core/theme/nexa_theme.dart';

class DeviceLinkQrScreen extends StatelessWidget {
  final String linkingCode;

  const DeviceLinkQrScreen({
    super.key,
    this.linkingCode = 'NX-LINK:9B1D-4K7M-84ZT:DEV_WIN_M4',
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexaColors.canvas,
      appBar: AppBar(
        title: const Text('Link New Device'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              const SizedBox(height: 12),
              // Explanatory Zero-Knowledge Banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: NexaColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: NexaColors.border),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.devices, color: NexaColors.cyanAccent, size: 24),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pairwise Key Agreement',
                            style: TextStyle(color: NexaColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Each device holds its own isolated cryptographic identity. Master keys are never transmitted.',
                            style: TextStyle(color: NexaColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Mock QR Display Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: NexaColors.cyanAccent.withValues(alpha: 0.25),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Mock QR Visual grid
                    Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Icon(Icons.qr_code_2, color: Colors.white, size: 160),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      linkingCode,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 12,
                        fontFamily: 'Courier',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              const Text(
                'Point your primary phone camera at this QR code to authorize this device.',
                textAlign: TextAlign.center,
                style: TextStyle(color: NexaColors.textSecondary, fontSize: 14),
              ),

              const Spacer(),

              // Action Buttons
              ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Device authorization successful! Double Ratchet session initialized.'),
                      backgroundColor: NexaColors.elevated,
                    ),
                  );
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Simulate Approval from Phone'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
