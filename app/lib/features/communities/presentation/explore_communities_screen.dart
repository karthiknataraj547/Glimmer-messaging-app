import 'package:flutter/material.dart';
import '../../../core/theme/nexa_theme.dart';
import 'community_channel_screen.dart';

class ExploreCommunitiesScreen extends StatefulWidget {
  const ExploreCommunitiesScreen({super.key});

  @override
  State<ExploreCommunitiesScreen> createState() => _ExploreCommunitiesScreenState();
}

class _ExploreCommunitiesScreenState extends State<ExploreCommunitiesScreen> {
  String _selectedCategory = 'All';

  final List<String> _categories = [
    'All',
    '🤖 AI',
    '⚡ Electronics',
    '🌱 Smart Agriculture',
    '💻 Programming',
  ];

  final List<Map<String, dynamic>> _communities = [
    {
      'name': 'AI Builders',
      'category': '🤖 AI',
      'members': 1240,
      'description': 'Engineers building quantized on-device LLMs, local SLMs, and privacy-first agents.',
      'channels': ['announcements', 'research', 'hardware'],
    },
    {
      'name': 'IoT Developers',
      'category': '⚡ Electronics',
      'members': 3420,
      'description': 'Schematics, ESP32/ARM firmware, low-power telemetry, and hardware debugging.',
      'channels': ['schematics', 'firmware', 'general'],
    },
    {
      'name': 'Smart Agriculture',
      'category': '🌱 Smart Agriculture',
      'members': 840,
      'description': 'Automated drip irrigation, soil telemetry nodes, and solar micro-grids.',
      'channels': ['sensors', 'irrigation', 'field-notes'],
    },
    {
      'name': 'Cryptographic Systems',
      'category': '💻 Programming',
      'members': 2100,
      'description': 'Zero-knowledge proofs, Double Ratchet implementations, and decentralized protocols.',
      'channels': ['zk-proofs', 'e2ee', 'protocols'],
    },
  ];

  @override
  Widget build(BuildContext context) {
    final filtered = _selectedCategory == 'All'
        ? _communities
        : _communities.where((c) => c['category'] == _selectedCategory).toList();

    return Scaffold(
      backgroundColor: NexaColors.canvas,
      appBar: AppBar(
        title: const Text('Explore Communities'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category Filter Bar
            SizedBox(
              height: 44,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final isSelected = cat == _selectedCategory;

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: isSelected,
                      selectedColor: NexaColors.cyanAccent,
                      backgroundColor: NexaColors.surface,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.black : NexaColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: isSelected ? NexaColors.cyanAccent : NexaColors.border,
                        ),
                      ),
                      onSelected: (_) => setState(() => _selectedCategory = cat),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),

            // Explanatory Quiet Discovery Banner
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Intentional spaces based on your selected interests. No algorithmic engagement feed.',
                style: TextStyle(color: NexaColors.textMuted, fontSize: 12),
              ),
            ),

            const SizedBox(height: 12),

            // Community Cards Stream
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final comm = filtered[index];
                  final channels = comm['channels'] as List<String>;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: NexaColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: NexaColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              comm['name'] as String,
                              style: const TextStyle(
                                color: NexaColors.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: NexaColors.elevated,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: NexaColors.border),
                              ),
                              child: Text(
                                '${comm['members']} members',
                                style: const TextStyle(color: NexaColors.textSecondary, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          comm['description'] as String,
                          style: const TextStyle(color: NexaColors.textSecondary, fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 14),

                        // Channel Pills
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: channels.map((channel) {
                            return InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CommunityChannelScreen(
                                    communityName: comm['name'] as String,
                                    channelName: channel,
                                    memberCount: comm['members'] as int,
                                  ),
                                ),
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: NexaColors.elevated,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: NexaColors.border),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('#', style: TextStyle(color: NexaColors.cyanAccent, fontWeight: FontWeight.bold)),
                                    const SizedBox(width: 4),
                                    Text(channel, style: const TextStyle(color: NexaColors.textPrimary, fontSize: 12)),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
