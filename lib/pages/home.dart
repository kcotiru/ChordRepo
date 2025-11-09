import 'package:flutter/material.dart';
import 'songs_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 1; // 0: Songs, 1: Home, 2: Settings


  Widget _buildHomeContent() {
    return ListView(
      padding: const EdgeInsets.only(top: 16),
      children: [
        // Welcome section
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                      color: const Color(0xFF1DB954),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: const Icon(
                      Icons.music_note,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome to Chord Repository',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Create and manage your chord progressions',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Quick stats or recent activity
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quick Start',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 12),
              Text(
                '• Go to Songs tab to add new songs\n• Create chord progressions for your songs\n• Organize your music library',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSongsContent() {
    return const SongsPage();
  }

  Widget _buildSettingsContent() {
    return const Center(
      child: Text(
        'Settings page - Configuration options will be here',
        style: TextStyle(color: Colors.white),
      ),
    );
  }

  Widget _buildScaffoldForIndex() {
    switch (_selectedIndex) {
      case 0:
        return Scaffold(
          appBar: AppBar(
            title: const Text('Songs'),
            backgroundColor: const Color(0xFF121212),
            foregroundColor: Colors.white,
          ),
          backgroundColor: const Color(0xFF121212),
          body: _buildSongsContent(),
          bottomNavigationBar: _buildBottomNav(),
        );
      case 2:
        return Scaffold(
          appBar: AppBar(
            title: const Text('Settings'),
            backgroundColor: const Color(0xFF121212),
            foregroundColor: Colors.white,
          ),
          backgroundColor: const Color(0xFF121212),
          body: _buildSettingsContent(),
          bottomNavigationBar: _buildBottomNav(),
        );
      case 1:
      default:
        return Scaffold(
          appBar: AppBar(
            title: const Text('Home'),
            backgroundColor: const Color(0xFF121212),
            foregroundColor: Colors.white,
          ),
          backgroundColor: const Color(0xFF121212),
          body: _buildHomeContent(),
          bottomNavigationBar: _buildBottomNav(),
        );
    }
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: (i) {
        setState(() => _selectedIndex = i);
      },
      backgroundColor: const Color(0xFF121212),
      selectedItemColor: const Color(0xFF1DB954),
      unselectedItemColor: Colors.grey,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.library_music), label: 'Songs'),
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildScaffoldForIndex();
  }
}
