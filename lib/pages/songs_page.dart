import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'song_view_page.dart';

final supabase = Supabase.instance.client;

class SongsPage extends StatefulWidget {
  const SongsPage({super.key});

  @override
  State<SongsPage> createState() => _SongsPageState();
}

class _SongsPageState extends State<SongsPage> {
  bool _addingSong = false;
  final _songNameController = TextEditingController();
  final _artistController = TextEditingController();
  final _keyController = TextEditingController();
  final _bpmController = TextEditingController();
  bool _loading = false;
  List<Map<String, dynamic>> _songs = [];

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  @override
  void dispose() {
    _songNameController.dispose();
    _artistController.dispose();
    _keyController.dispose();
    _bpmController.dispose();
    super.dispose();
  }

  Future<void> _loadSongs() async {
    try {
      final response = await supabase
          .from('songs')
          .select('id, name, artist, original_key, bpm, created_at')
          .order('created_at', ascending: false);

      setState(() {
        _songs = response.map((song) => Map<String, dynamic>.from(song)).toList();
      });
    } catch (e) {
      debugPrint('Error loading songs: $e');
    }
  }

  Future<void> _createSong() async {
    final songName = _songNameController.text.trim();
    final artist = _artistController.text.trim();
    final originalKey = _keyController.text.trim();
    final bpmText = _bpmController.text.trim();

    if (songName.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please enter a song name')));
      return;
    }

    setState(() => _loading = true);

    try {
      final response = await supabase.from('songs').insert({
        'name': songName,
        'artist': artist,
        'original_key': originalKey,
        'bpm': int.tryParse(bpmText),
      }).select('id').maybeSingle();

      if (response == null || response['id'] == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Error creating song.')));
      } else {
        final newSongId = response['id'] as String;
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SongViewPage(songId: newSongId, songName: songName),
            ),
          );
          // Refresh the songs list after returning
          _loadSongs();
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  Widget _buildAddSongForm() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add New Song',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _songNameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Song Name',
                labelStyle: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _artistController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Artist Name',
                labelStyle: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keyController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Original Key',
                labelStyle: TextStyle(color: Colors.grey),
              ),
              onChanged: (value) {
                // Convert lowercase letters to uppercase for musical keys (preserve diminished symbol and other chord symbols)
                final cursorPosition = _keyController.selection.baseOffset;
                final newValue = value.replaceAllMapped(
                  RegExp(r'[a-g]'),
                  (match) => match.group(0)!.toUpperCase(),
                );
                
                if (newValue != value) {
                  _keyController.value = TextEditingValue(
                    text: newValue,
                    selection: TextSelection.collapsed(offset: cursorPosition),
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bpmController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'BPM',
                labelStyle: TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _loading ? null : _createSong,
                  icon: _loading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check),
                  label: const Text('Create'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () => setState(() {
                            _addingSong = false;
                            _songNameController.clear();
                            _artistController.clear();
                            _keyController.clear();
                            _bpmController.clear();
                          }),
                  child: const Text('Cancel'),
                )
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSongList() {
    if (_songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.music_note,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            const Text(
              'No songs yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap the + button to add your first song',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _songs.length,
      itemBuilder: (context, index) {
        final song = _songs[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFF1DB954).withOpacity(0.2),
                borderRadius: BorderRadius.circular(25),
              ),
              child: const Icon(
                Icons.music_note,
                color: Color(0xFF1DB954),
                size: 24,
              ),
            ),
            title: Text(
              song['name'] ?? 'Untitled',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 16,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (song['artist'] != null && song['artist'].isNotEmpty)
                  Text(
                    song['artist'] ?? '',
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (song['original_key'] != null && song['original_key'].isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1DB954).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          song['original_key'] ?? '',
                          style: const TextStyle(
                            color: Color(0xFF1DB954),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    if (song['bpm'] != null)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${song['bpm']} BPM',
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            trailing: const Icon(
              Icons.arrow_forward_ios,
              color: Colors.grey,
              size: 16,
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SongViewPage(songId: song['id'], songName: song['name'] ?? 'Untitled'),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Songs'),
        backgroundColor: const Color(0xFF121212),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFF121212),
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          Expanded(
            child: _buildSongList(),
          ),
          if (_addingSong) _buildAddSongForm(),
        ],
      ),
      floatingActionButton: !_addingSong
          ? FloatingActionButton(
              onPressed: () => setState(() => _addingSong = true),
              backgroundColor: const Color(0xFF1DB954),
              child: const Icon(Icons.add, color: Colors.white),
              tooltip: 'Add Song',
            )
          : null,
    );
  }
}
