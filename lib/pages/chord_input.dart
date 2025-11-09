import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class ChordInputPage extends StatefulWidget {
  final String songId;
  final String songName;

  const ChordInputPage({
    super.key,
    required this.songId,
    required this.songName,
  });

  @override
  State<ChordInputPage> createState() => _ChordInputPageState();
}

class _ChordInputPageState extends State<ChordInputPage> {
  final Map<String, TextEditingController> _sectionControllers = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSections();
  }

  Future<void> _loadSections() async {
    setState(() => _loading = true);

    try {
      // Fetch sections
      final sections = await supabase
          .from('sections')
          .select('id, name, order_index')
          .eq('song_id', widget.songId)
          .order('order_index');

      for (final section in sections) {
        final sectionId = section['id'] as String;
        final controller = TextEditingController();

        // Load existing bars & chords into text format
        final bars = await supabase
            .from('bars')
            .select('id, bar_order, repeat_count, starts_new_line')
            .eq('section_id', sectionId)
            .order('bar_order', ascending: true);

        if (bars.isNotEmpty) {
          String sectionText = '';
          bool isFirstBar = true;
          int sectionRepeatCount = 1;
          
          for (final bar in bars) {
            final barId = bar['id'] as String;
            final repeatCount = bar['repeat_count'] as int? ?? 1;
            final startsNewLine = bar['starts_new_line'] as bool? ?? false;
            
            // Use the repeat count from the first bar as the section repeat count
            if (isFirstBar) {
              sectionRepeatCount = repeatCount;
            }
            
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
          if (sectionRepeatCount > 1) {
            sectionText += ' ($sectionRepeatCount' + 'x)';
          }
          
          controller.text = sectionText;
        }

        _sectionControllers[sectionId] = controller;
      }
    } catch (e) {
      debugPrint('Error loading sections: $e');
      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading sections: $e')),
        );
      }
    }

    setState(() => _loading = false);
  }

  Future<List<Map<String, dynamic>>> _getSectionsInOrder() async {
    final sections = await supabase
        .from('sections')
        .select('id, name, order_index')
        .eq('song_id', widget.songId)
        .order('order_index');
    
    return sections.map((section) => Map<String, dynamic>.from(section)).toList();
  }

  Future<void> _addSection() async {
    debugPrint('Add section button pressed');
    final nameController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Add Section',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Section Name',
            labelStyle: TextStyle(color: Colors.grey),
            hintText: 'e.g. Verse, Chorus, Bridge',
            hintStyle: TextStyle(color: Colors.grey),
            filled: true,
            fillColor: Color(0xFF121212),
            border: OutlineInputBorder(),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF1DB954)),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1DB954),
              foregroundColor: Colors.white,
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == true) {
      final name = nameController.text.trim();
      if (name.isNotEmpty) {
        try {
          // Get the current number of sections to set correct order_index
          final existingSections = await supabase
              .from('sections')
              .select('id')
              .eq('song_id', widget.songId);
          
          final orderIndex = existingSections.length + 1;
          final newSection = await supabase
              .from('sections')
              .insert({
                'song_id': widget.songId,
                'name': name,
                'order_index': orderIndex,
              })
              .select()
              .single();

          _sectionControllers[newSection['id']] = TextEditingController();
          setState(() {});
          debugPrint('Section added successfully: ${newSection['id']}');
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Section "$name" added successfully!')),
            );
          }
        } catch (e) {
          debugPrint('Error adding section: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error adding section: $e')),
            );
          }
        }
      }
    }
  }

  Future<void> _saveSection(String sectionId) async {
    final text = _sectionControllers[sectionId]!.text.trim();

    try {
      // Delete existing bars/chords for this section to replace them cleanly
      await supabase.from('bars').delete().eq('section_id', sectionId);

      if (text.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Section cleared')),
          );
        }
        return;
      }

      // Check for repeat count in parentheses like (4x) at the end of the entire section
      int sectionRepeatCount = 1;
      String processedText = text;
      
      // Look for repeat pattern at the very end
      final sectionRepeatMatch = RegExp(r'\s*\((\d+)x\)\s*$').firstMatch(text);
      if (sectionRepeatMatch != null) {
        sectionRepeatCount = int.tryParse(sectionRepeatMatch.group(1)!) ?? 1;
        processedText = text.replaceAll(RegExp(r'\s*\(\d+x\)\s*$'), '').trim();
      }

      // Split by | but preserve line break information
      final lines = processedText.split('\n');
      List<Map<String, dynamic>> barsWithLineBreaks = [];
      
      for (int lineIndex = 0; lineIndex < lines.length; lineIndex++) {
        final line = lines[lineIndex];
        final bars = line
            .split('|')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
            
        for (int barIndex = 0; barIndex < bars.length; barIndex++) {
          barsWithLineBreaks.add({
            'text': bars[barIndex],
            'isNewLine': lineIndex > 0 && barIndex == 0, // First bar of a new line
          });
        }
      }
      int barOrder = 1;

      for (final barData in barsWithLineBreaks) {
        final barText = barData['text'] as String;
        final isNewLine = barData['isNewLine'] as bool;
        final chords = barText.trim().split(RegExp(r'\s+'));
        if (chords.isEmpty || chords.every((c) => c.isEmpty)) continue;

        // Insert bar with section repeat count and line break info
        final bar = await supabase.from('bars').insert({
          'section_id': sectionId,
          'bar_order': barOrder++,
          'repeat_count': sectionRepeatCount,
          'starts_new_line': isNewLine,
        }).select().single();

        // Insert chords (limit to 4 positions)
        for (int i = 0; i < chords.length && i < 4; i++) {
          final chord = chords[i].trim();
          if (chord.isNotEmpty) {
            await supabase.from('chords_in_bar').insert({
              'bar_id': bar['id'],
              'position': i + 1,
              'chord': chord,
            });
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Section saved successfully!')),
        );
      }
    } catch (e) {
      debugPrint('Error saving section: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving section: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Chords: ${widget.songName}'),
        backgroundColor: const Color(0xFF121212),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF1DB954)),
            tooltip: 'Add Section',
            onPressed: _addSection,
          ),
        ],
      ),
      backgroundColor: const Color(0xFF121212),
      resizeToAvoidBottomInset: true,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1DB954)))
          : _sectionControllers.isEmpty
              ? Center(
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
                        'No sections yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Add a section to start creating chord progressions',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _addSection,
                        icon: const Icon(Icons.add),
                        label: const Text('Add First Section'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1DB954),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), // Extra bottom padding for keyboard
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _getSectionsInOrder(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: Color(0xFF1DB954)));
                      }
                      
                      final sectionsInOrder = snapshot.data ?? [];
                      return Column(
                        children: sectionsInOrder.map((sectionData) {
                        final sectionId = sectionData['id'] as String;
                        final controller = _sectionControllers[sectionId]!;
                        return Container(
                      margin: const EdgeInsets.only(bottom: 24),
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
                            FutureBuilder(
                              future: supabase
                                  .from('sections')
                                  .select('name')
                                  .eq('id', sectionId)
                                  .maybeSingle(),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  return const Text(
                                    'Loading section...',
                                    style: TextStyle(color: Colors.grey),
                                  );
                                }
                                final sectionName = snapshot.data?['name'] ?? 'Untitled';
                                return Row(
                                children: [
                                    const Icon(
                                      Icons.music_note,
                                      color: Color(0xFF1DB954),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                  Expanded(
                                      child: Text(
                                        sectionName,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _deleteSection(sectionId),
                                      tooltip: 'Delete Section',
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF121212),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
                              ),
                              child: TextField(
                                controller: controller,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.all(16),
                                  hintText: 'Type chords like: | D | D5 | (4x)',
                                  hintStyle: TextStyle(
                                    color: Colors.grey,
                                    fontFamily: 'monospace',
                                    fontSize: 14,
                                  ),
                                ),
                                maxLines: null,
                                keyboardType: TextInputType.multiline,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 16,
                                  color: Colors.white,
                                  height: 1.5,
                                ),
                                onChanged: (value) {
                                  // Convert lowercase letters to uppercase (preserve diminished symbol and other chord symbols)
                                  final cursorPosition = controller.selection.baseOffset;
                                  final newValue = value.replaceAllMapped(
                                    RegExp(r'[a-g]'),
                                    (match) => match.group(0)!.toUpperCase(),
                                  );
                                  
                                  if (newValue != value) {
                                    controller.value = TextEditingValue(
                                      text: newValue,
                                      selection: TextSelection.collapsed(offset: cursorPosition),
                                    );
                                  }
                                },
                              ),
                            ),
                            const SizedBox(height: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Chord symbol buttons for easier mobile input
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    _buildChordButton('|', controller),
                                    _buildChordButton('#', controller),
                                    _buildChordButton('b', controller),
                                    _buildChordButton('maj', controller),
                                    _buildChordButton('m', controller),
                                    _buildChordButton('°', controller),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.save, size: 18),
                                  label: const Text('Save'),
                                  onPressed: () => _saveSection(sectionId),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1DB954),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton(
                        onPressed: _addSection,
        backgroundColor: const Color(0xFF1DB954),
        child: const Icon(Icons.add, color: Colors.white),
        tooltip: 'Add Section',
      ),
    );
  }

  Widget _buildChordButton(String symbol, TextEditingController controller) {
    return ElevatedButton(
      onPressed: () {
        final currentText = controller.text;
        final cursorPosition = controller.selection.baseOffset;
        final newText = currentText.substring(0, cursorPosition) + 
                       symbol + 
                       currentText.substring(cursorPosition);
        controller.text = newText;
        controller.selection = TextSelection.collapsed(
          offset: cursorPosition + symbol.length,
        );
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF2A2A2A),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(36, 28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      child: Text(
        symbol,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _deleteSection(String sectionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Delete Section',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to delete this section? This action cannot be undone.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
                      ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
              ],
            ),
    );

    if (confirmed == true) {
      try {
        // Get the order_index of the section being deleted
        final sectionToDelete = await supabase
            .from('sections')
            .select('order_index')
            .eq('id', sectionId)
            .single();
        
        final deletedOrderIndex = sectionToDelete['order_index'] as int;
        
        // Delete the section and its bars/chords
        await supabase.from('bars').delete().eq('section_id', sectionId);
        await supabase.from('sections').delete().eq('id', sectionId);
        
        // Reorder remaining sections
        final remainingSections = await supabase
            .from('sections')
            .select('id, order_index')
            .gt('order_index', deletedOrderIndex)
            .eq('song_id', widget.songId)
            .order('order_index');
        
        for (final section in remainingSections) {
          final newOrderIndex = (section['order_index'] as int) - 1;
          await supabase
              .from('sections')
              .update({'order_index': newOrderIndex})
              .eq('id', section['id']);
        }
        
        _sectionControllers.remove(sectionId);
        setState(() {});
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Section deleted')),
          );
        }
      } catch (e) {
        debugPrint('Error deleting section: $e');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting section: $e')),
          );
        }
      }
    }
  }
}
