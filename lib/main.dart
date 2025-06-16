import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:share_plus/share_plus.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = RequestConfiguration(testDeviceIds: ['40a7628bba9c83845e9fc979bb7b38ea']);
  MobileAds.instance.updateRequestConfiguration(config);
  await MobileAds.instance.initialize();
  runApp(const MakeCutApp());
}

class MakeCutApp extends StatelessWidget {
  const MakeCutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const MakeCutHome(),
    );
  }
}

class MakeCutHome extends StatefulWidget {
  const MakeCutHome({super.key});
  @override
  State<MakeCutHome> createState() => _MakeCutHomeState();
}
class _MakeCutHomeState extends State<MakeCutHome> {
  final TextEditingController _urlController = TextEditingController();
  bool isAudioEnabled = true;
  String selectedQuality = '1080p';
  String status = '';
  bool showStatus = false;

  bool _hasShownStartupAd = false;
  RewardedAd? _rewardedAd;
  bool _isAdReady = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
    Future.delayed(const Duration(seconds: 3), () {
      if (_isAdReady && !_hasShownStartupAd) {
        _rewardedAd?.show(onUserEarnedReward: (ad, reward) {
          _hasShownStartupAd = true;
        });
      }
    });
  }

  void _loadAd() {
    RewardedAd.load(
      adUnitId: 'ca-app-pub-3940256099942544/1712485313', // Test Ad
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          setState(() {
            _rewardedAd = ad;
            _isAdReady = true;
          });
        },
        onAdFailedToLoad: (error) {
          _isAdReady = false;
        },
      ),
    );
  }

  void _handleDownloadPressed() {
    if (_isAdReady) {
      _rewardedAd?.show(onUserEarnedReward: (ad, reward) {
        downloadVideo();
        _loadAd();
      });
    } else {
      showTempMessage("Ad not ready. Starting download anyway.");
      downloadVideo();
      _loadAd();
    }
  }

  Future<String> resolveRedirect(String url) async {
    final res = await http.get(Uri.parse(url));
    return res.request?.url.toString() ?? url;
  }

  Future<void> downloadVideo() async {
    final inputUrl = _urlController.text.trim();
    if (inputUrl.isEmpty) {
      showTempMessage('Please enter a video URL.');
      return;
    }

    final url = await resolveRedirect(inputUrl);

    showTempMessage('Downloading...');
    try {
      final response = await http.post(
        Uri.parse('https://makecut-backend.onrender.com/download'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'url': url,
          'audio': isAudioEnabled,
          'quality': selectedQuality,
        }),
      );

      final result = jsonDecode(response.body);
      if (result['status'] == 'success') {
        final filePath = '${result['path']}/${result['file']}';
        await GallerySaver.saveVideo(filePath, toDcim: true, albumName: 'MakeCut');
        showTempMessage('Saved to gallery!');
      } else {
        showTempMessage('Failed: ${result['message']}');
      }
    } catch (e) {
      showTempMessage('Error: $e');
    }
  }
  void showTempMessage(String msg) {
    setState(() {
      status = msg;
      showStatus = true;
    });

    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => showStatus = false);
      }
    });
  }

  void toggleAudio() {
    setState(() {
      isAudioEnabled = !isAudioEnabled;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topLeft,
            radius: 2.5,
            colors: [Color(0x22FFFFFF), Colors.transparent, Colors.black],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 40),
              const Text(
                'MAKECUT',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'DOWNLOADER',
                style: TextStyle(
                  fontSize: 16,
                  letterSpacing: 3,
                  color: Color(0xFF888888),
                ),
              ),
              const SizedBox(height: 20),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 420,
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161616),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: _urlController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            filled: true,
                            fillColor: Color(0xFF1A1A1A),
                            hintText: 'Enter the video URL',
                            hintStyle: TextStyle(color: Colors.grey),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(12)),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1F1F1F),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white30),
                              ),
                              child: DropdownButton<String>(
                                value: selectedQuality,
                                dropdownColor: const Color(0xFF1F1F1F),
                                style: const TextStyle(color: Colors.white),
                                underline: const SizedBox(),
                                iconEnabledColor: Colors.white,
                                items: ['1080p', '720p', '480p', '360p']
                                    .map((value) => DropdownMenuItem(
                                          value: value,
                                          child: Text(value),
                                        ))
                                    .toList(),
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() => selectedQuality = value);
                                  }
                                },
                              ),
                            ),
                            Row(
                              children: [
                                Switch(
                                  value: isAudioEnabled,
                                  onChanged: (value) =>
                                      setState(() => isAudioEnabled = value),
                                  activeColor: Colors.white,
                                  inactiveThumbColor: Colors.grey,
                                  inactiveTrackColor: Colors.grey.shade800,
                                ),
                                const SizedBox(width: 4),
                                const Text('Audio', style: TextStyle(color: Colors.white)),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _handleDownloadPressed,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            backgroundColor: const Color(0xFF1F1F1F),
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white30),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Download',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 20),
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => DownloadHistoryScreen()),
                             );
                            }, // 👈 ADD THIS COMMA RIGHT HERE
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF1C1C1C),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white30),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.folder, color: Colors.white),
                                  SizedBox(width: 10),
                                  Text('View Download History', style: TextStyle(color: Colors.white)),
                                  SizedBox(width: 10),
                                  Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: -22,
                    right: 0,
                    child: GestureDetector(
                      onTap: toggleAudio,
                      child: Icon(
                        isAudioEnabled ? Icons.volume_up : Icons.volume_off,
                        color: isAudioEnabled ? Colors.white : Colors.red,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              AnimatedOpacity(
                opacity: showStatus ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 500),
                child: Text(status, style: const TextStyle(color: Colors.greenAccent)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
class DownloadHistoryScreen extends StatefulWidget {
  const DownloadHistoryScreen({super.key});

  @override
  State<DownloadHistoryScreen> createState() => _DownloadHistoryScreenState();
}

class _DownloadHistoryScreenState extends State<DownloadHistoryScreen> {
  List<Map<String, dynamic>> videos = [];
  bool autoSave = true;

  @override
  void initState() {
    super.initState();
    fetchHistory();
    fetchAutoSaveStatus();
  }

  Future<void> fetchAutoSaveStatus() async {
    final response = await http.get(Uri.parse('https://makecut-backend.onrender.com/autosave'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        autoSave = data['enabled'] ?? true;
      });
    }
  }

  Future<void> updateAutoSave(bool value) async {
    setState(() => autoSave = value);
    await http.post(
      Uri.parse('https://makecut-backend.onrender.com/autosave'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'enabled': value}),
    );
  }

  Future<void> fetchHistory() async {
    final response = await http.get(Uri.parse('https://makecut-backend.onrender.com/history'));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        videos = List<Map<String, dynamic>>.from(data);
      });
    }
  }

  void shareFile(String path) {
    Share.shareXFiles([XFile(path)]);
  }

  void deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
    fetchHistory();
  }

  void renameFile(String oldPath, String newName) async {
    final dir = File(oldPath).parent;
    final newPath = path.join(dir.path, newName);
    try {
      await File(oldPath).rename(newPath);
      fetchHistory();
    } catch (_) {}
  }

  Future<void> saveToGallery(String path) async {
    try {
      await GallerySaver.saveVideo(path, toDcim: true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to Gallery'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topLeft,
                radius: 2.5,
                colors: [Color(0x22FFFFFF), Colors.transparent, Colors.black],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
            padding: const EdgeInsets.only(top: 60),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Icon(Icons.arrow_back, color: Colors.white),
                        ),
                      ),
                      const Text(
                        'Download History',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Column(
                        children: [
                          const Text('AutoSave', style: TextStyle(fontSize: 14, color: Colors.white)),
                          Switch(
                            value: autoSave,
                            onChanged: updateAutoSave,
                            activeColor: Colors.white,
                            inactiveThumbColor: Colors.grey,
                            inactiveTrackColor: Colors.grey.shade800,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white24, thickness: 0.5),
                Expanded(
                  child: videos.isEmpty
                      ? const Center(
                          child: Text("No videos found.", style: TextStyle(color: Colors.white54)),
                        )
                      : ListView.builder(
                          itemCount: videos.length,
                          itemBuilder: (_, index) {
                            final fileData = videos[index];
                            final filePath = fileData['path'];
                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 32),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1A1A),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: ListTile(
                                leading: const Icon(Icons.video_file, color: Colors.white, size: 32),
                                title: Text(fileData['filename'], style: const TextStyle(color: Colors.white)),
                                subtitle: Text(fileData['size'], style: const TextStyle(color: Colors.white70)),
                                trailing: PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, color: Colors.white),
                                  onSelected: (value) {
                                    if (value == 'Save') {
                                      saveToGallery(filePath);
                                    } else if (value == 'Share') {
                                      shareFile(filePath);
                                    } else if (value == 'Delete') {
                                      deleteFile(filePath);
                                    } else if (value == 'Rename') {
                                      showDialog(
                                        context: context,
                                        builder: (context) {
                                          final controller = TextEditingController();
                                          return AlertDialog(
                                            backgroundColor: Colors.black87,
                                            title: const Text('Rename File', style: TextStyle(color: Colors.white)),
                                            content: TextField(
                                              controller: controller,
                                              style: const TextStyle(color: Colors.white),
                                              decoration: const InputDecoration(
                                                hintText: 'Enter new file name',
                                                hintStyle: TextStyle(color: Colors.white70),
                                              ),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(context),
                                                child: const Text('Cancel', style: TextStyle(color: Colors.red)),
                                              ),
                                              TextButton(
                                                onPressed: () {
                                                  renameFile(filePath, controller.text);
                                                  Navigator.pop(context);
                                                },
                                                child: const Text('Rename', style: TextStyle(color: Colors.green)),
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                    }
                                  },
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(value: 'Save', child: Text('Save to Gallery')),
                                    PopupMenuItem(value: 'Share', child: Text('Share')),
                                    PopupMenuItem(value: 'Rename', child: Text('Rename')),
                                    PopupMenuItem(value: 'Delete', child: Text('Delete')),
                                  ],
                                ),
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
    );
  }
}
