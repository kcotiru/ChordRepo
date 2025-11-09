import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chord_input.dart';

final supabase = Supabase.instance.client;

class SongViewPage extends StatefulWidget {
  final String songId;
  final String songName;

  const SongViewPage({
    super.key,
    required this.songId,
    required this.songName,
  });

  @override
  State<SongViewPage> createState() => _SongViewPageState();
}

class _SongViewPageState extends State<SongViewPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _sections = [];
  String? _originalKey;
  String? _currentKey;
  int _transposeSteps = 0;
  String _originalText = ''; // Store the original untransposed text

  @override
  void initState() {
    super.initState();
    _loadSongStructure();
  }

  Future<void> _loadSongStructure() async {
    setState(() => _loading = true);

    try {
      // Load song information including original key
      final song = await supabase
          .from('songs')
          .select('original_key')
          .eq('id', widget.songId)
          .maybeSingle();
      
      if (song != null) {
        _originalKey = song['original_key'] as String?;
        _currentKey = _originalKey;
        _transposeSteps = 0; // Reset transpose steps when loading
      }

      // Load sections with their bars and chords
      final sections = await supabase
          .from('sections')
          .select('id, name, order_index')
          .eq('song_id', widget.songId)
          .order('order_index');

      // Sort sections by order_index to ensure correct display order (ascending)
      sections.sort((a, b) => (a['order_index'] as int).compareTo(b['order_index'] as int));

      List<Map<String, dynamic>> sectionsData = [];

      for (final section in sections) {
        final sectionId = section['id'] as String;
        final sectionName = section['name'] as String;
        final orderIndex = section['order_index'] as int;

        // Get bars for this section
        final bars = await supabase
            .from('bars')
            .select('id, bar_order, repeat_count, starts_new_line')
            .eq('section_id', sectionId)
            .order('bar_order', ascending: true);

        // Reconstruct the text with preserved line breaks
        String sectionText = '';
        bool isFirstBar = true;
        
        for (final bar in bars) {
          final barId = bar['id'] as String;
          final startsNewLine = bar['starts_new_line'] as bool? ?? false;

          // Get chords for this bar
          final chords = await supabase
              .from('chords_in_bar')
              .select('chord, position')
              .eq('bar_id', barId)
              .order('position', ascending: true);

          // Create chord list with proper positioning
          List<String> chordList = ['', '', '', ''];
          for (final chord in chords) {
            final position = (chord['position'] as int) - 1; // Convert to 0-based
            final chordText = chord['chord'] as String? ?? '';
            if (position >= 0 && position < 4) {
              chordList[position] = chordText;
            }
          }

          // Join chords and filter out empty strings, only show dashes if explicitly inputted
          String barText = chordList.where((chord) => chord.isNotEmpty).join(' ').trim();
          
          if (isFirstBar) {
            sectionText += '| $barText';
            isFirstBar = false;
          } else if (startsNewLine) {
            sectionText += ' |\n| $barText';
          } else {
            sectionText += ' | $barText';
          }
        }
        
        sectionText += ' |';
        
        // Check if all bars have the same repeat count > 1
        if (bars.isNotEmpty) {
          final firstBarRepeatCount = bars.first['repeat_count'] as int? ?? 1;
          if (firstBarRepeatCount > 1) {
            sectionText += ' ($firstBarRepeatCount' + 'x)';
          }
        }

        sectionsData.add({
          'id': sectionId,
          'name': sectionName,
          'order_index': orderIndex,
          'text': sectionText,
        });
      }

      // Combine all sections into one text block with section names and line breaks
      String combinedText = '';
      for (int i = 0; i < sectionsData.length; i++) {
        final section = sectionsData[i];
        final sectionName = section['name'] as String;
        final sectionText = section['text'] as String;
        
        // Add section name
        combinedText += '$sectionName:\n';
        // Add section chords
        combinedText += sectionText;
        
        // Add blank line between sections (except for the last one)
        if (i < sectionsData.length - 1) {
          combinedText += '\n\n';
        }
      }

      // Store the original text for transposition
      _originalText = combinedText;
      
      setState(() {
        _sections = [{'combined_text': combinedText}];
      });
    } catch (e) {
      debugPrint('Error loading song structure: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading song: $e')),
        );
      }
    }

    setState(() => _loading = false);
  }

  // Enhanced chord transposition logic
  String _transposeChord(String chord, int steps) {
    if (chord.isEmpty || chord == '-') return chord;
    
    // Handle slash chords (like C/E, F#/A#)
    if (chord.contains('/')) {
      final parts = chord.split('/');
      if (parts.length == 2) {
        final rootChord = _transposeChord(parts[0], steps);
        final bassNote = _transposeChord(parts[1], steps);
        return '$rootChord/$bassNote';
      }
    }
    
    // Define the chromatic scale with both sharps and flats
    final chromaticScaleSharp = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final chromaticScaleFlat = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'];
    
    // More comprehensive chord parsing that preserves parentheses
    String rootNote = '';
    String suffix = '';
    
    // Use regex to properly extract root note and suffix (including diminished symbol)
    final chordPattern = RegExp(r'^([A-G][#b]?)(.*)$');
    final match = chordPattern.firstMatch(chord);
    
    if (match != null) {
      rootNote = match.group(1)!;
      suffix = match.group(2)!;
    } else {
      // Fallback: if no match, treat entire chord as root note
      rootNote = chord;
      suffix = '';
    }
    
    // Find the current note index in sharp scale
    int currentIndex = chromaticScaleSharp.indexOf(rootNote);
    if (currentIndex == -1) {
      // Try flat scale
      currentIndex = chromaticScaleFlat.indexOf(rootNote);
      if (currentIndex == -1) {
        // If still not found, return original chord
        return chord;
      }
    }
    
    // Calculate new index with transpose steps
    int newIndex = (currentIndex + steps) % 12;
    if (newIndex < 0) newIndex += 12;
    
    // Choose appropriate scale for output (prefer sharps for most cases)
    String newRootNote = chromaticScaleSharp[newIndex];
    
    // Return transposed chord
    return newRootNote + suffix;
  }

  String _transposeText(String text, int steps) {
    if (steps == 0) return text;
    
    // Split text into lines and process each line
    final lines = text.split('\n');
    final transposedLines = lines.map((line) {
      // Skip section name lines (lines that end with ':')
      if (line.trim().endsWith(':')) return line;
      
      // Process chord lines with more robust chord detection
      return line.split(' ').map((word) {
        // Clean the word (remove any trailing punctuation except for chord symbols, parentheses, and diminished symbol)
        String cleanWord = word.replaceAll(RegExp(r'[^\w#b/()°]'), '');
        
        // Check if it looks like a chord using multiple criteria
        if (_isChord(cleanWord)) {
          return _transposeChord(cleanWord, steps);
        }
        return word;
      }).join(' ');
    }).toList();
    
    return transposedLines.join('\n');
  }

  // Helper method to determine if a word is likely a chord
  bool _isChord(String word) {
    if (word.isEmpty || word.length < 1) return false;
    
    // Must start with a note letter (A-G)
    if (!RegExp(r'^[A-G]').hasMatch(word)) return false;
    
    // Check for valid chord patterns
    // Pattern 1: Basic note (C, D, E, F, G, A, B)
    if (RegExp(r'^[A-G]$').hasMatch(word)) return true;
    
    // Pattern 2: Note with sharp/flat (C#, Db, F#, Bb)
    if (RegExp(r'^[A-G][#b]$').hasMatch(word)) return true;
    
    // Pattern 3: Note with chord suffix - more flexible pattern
    // Matches: Cm, D7, Em7, F#maj7, Bb7, Am7(4), C°, etc.
    if (RegExp(r'^[A-G][#b]?[a-zA-Z0-9()°]*$').hasMatch(word)) return true;
    
    // Pattern 4: Complex chords with slashes (C/E, F#/A#)
    if (RegExp(r'^[A-G][#b]?[a-zA-Z0-9()°]*/[A-G][#b]?$').hasMatch(word)) return true;
    
    return false;
  }

  void _showTransposeDialog() {
    final keys = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Transpose Key',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_originalKey != null)
              Text(
                'Original Key: $_originalKey',
                style: const TextStyle(color: Colors.grey),
              ),
            const SizedBox(height: 16),
            const Text(
              'Select new key:',
              style: TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: keys.map((key) {
                final isSelected = _currentKey == key;
                return GestureDetector(
                  onTap: () {
                    if (_originalKey != null) {
                      final originalIndex = keys.indexOf(_originalKey!);
                      final newIndex = keys.indexOf(key);
                      final steps = newIndex - originalIndex;
                      
                      setState(() {
                        _currentKey = key;
                        _transposeSteps = steps;
                      });
                      
                      // Transpose the sections
                      _transposeSections();
                    }
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF1DB954) : const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF1DB954) : const Color(0xFF2A2A2A),
                      ),
                    ),
                    child: Text(
                      key,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          if (_originalKey != null && _currentKey != _originalKey)
            TextButton(
              onPressed: () {
                // Reset to original key
                setState(() {
                  _currentKey = _originalKey;
                  _transposeSteps = 0;
                });
                _transposeSections();
                Navigator.pop(context);
              },
              child: const Text('Reset to Original'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _transposeSections() {
    if (_originalText.isNotEmpty) {
      // Always transpose from the original text, not from the current transposed text
      final transposedText = _transposeText(_originalText, _transposeSteps);
      
      setState(() {
        _sections = [{'combined_text': transposedText}];
      });
    }
  }

  Widget _buildStyledChordText(String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    
    final List<TextSpan> spans = [];
    final lines = text.split('\n');
    
    for (int lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      
      // Check if this is a section name line (ends with ':')
      if (line.trim().endsWith(':')) {
        spans.add(TextSpan(
          text: line,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 16,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ));
      } else {
        // Process chord line - make chords bold, keep bars and dashes normal
        final words = line.split(' ');
        for (int wordIndex = 0; wordIndex < words.length; wordIndex++) {
          final word = words[wordIndex];
          
          if (word == '|') {
            spans.add(TextSpan(
              text: '|',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.normal,
              ),
            ));
          } else if (word == '-') {
            spans.add(TextSpan(
              text: '-',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.normal,
              ),
            ));
          } else {
            // This is a chord - make it bold
            spans.add(TextSpan(
              text: word,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ));
          }
          
          // Add space between words (except for the last word)
          if (wordIndex < words.length - 1) {
            spans.add(const TextSpan(text: ' '));
          }
        }
      }
      
      // Add newline between lines (except for the last line)
      if (lineIndex < lines.length - 1) {
        spans.add(const TextSpan(text: '\n'));
      }
    }
    
    return Container(
      height: null, // Let it size naturally
      child: RichText(
        text: TextSpan(children: spans),
      ),
    );
  }


  Widget _buildEmptyState() {
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
            'No chord progressions yet',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap "Edit Chords" to add chord progressions',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _navigateToEdit(),
            icon: const Icon(Icons.edit),
            label: const Text('Edit Chords'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1DB954),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToEdit() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChordInputPage(
          songId: widget.songId,
          songName: widget.songName,
        ),
      ),
    ).then((_) {
      // Refresh the view when returning from edit
      _loadSongStructure();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.songName} - Chords'),
        backgroundColor: const Color(0xFF121212),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Color(0xFF1DB954)),
            tooltip: 'Edit Chords',
            onPressed: _navigateToEdit,
          ),
        ],
      ),
      backgroundColor: const Color(0xFF121212),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1DB954)))
          : _sections.isEmpty
              ? _buildEmptyState()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Header
                    Container(
                      margin: const EdgeInsets.only(bottom: 24),
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1DB954).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                child: const Icon(
                                  Icons.music_note,
                                  color: Color(0xFF1DB954),
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.songName,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Chord Progressions',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _showTransposeDialog,
                                icon: const Icon(Icons.tune, size: 18),
                                label: Text(_currentKey != null ? 'Transpose ($_currentKey)' : 'Transpose'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1DB954),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Combined sections in single container
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
                      ),
                      child: _buildStyledChordText(
                        _sections.isNotEmpty ? _sections.first['combined_text'] : '',
                      ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToEdit,
        backgroundColor: const Color(0xFF1DB954),
        child: const Icon(Icons.edit, color: Colors.white),
        tooltip: 'Edit Chords',
      ),
    );
  }
}
