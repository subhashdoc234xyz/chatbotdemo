import 'dart:convert';

// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MindfulChatApp());

const ink = Color(0xFF16231D);
const forest = Color(0xFF356B50);
const canvas = Color(0xFFF6F7F3);
const muted = Color(0xFF7D8981);
const sage = Color(0xFFE4EBDD);

class MindfulChatApp extends StatelessWidget {
  const MindfulChatApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mori — a little clarity',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: canvas,
      colorScheme: ColorScheme.fromSeed(seedColor: forest),
      fontFamily: 'Roboto',
    ),
    home: const ChatPage(),
  );
}

class ChatMessage {
  const ChatMessage(this.text, {required this.fromUser, this.time});
  final String text;
  final bool fromUser;
  final String? time;
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _sending = false;
  String? _groqApiKey;
  bool _showApiKey = false;

  // For local web, use localhost. Override this for Android emulators/phones.
  static const _apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _groqApiKey = prefs.getString('groq_api_key'));
  }

  Future<void> _openSettings() async {
    final controller = TextEditingController(text: _groqApiKey ?? '');
    var showKey = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Groq API key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Use your own key for Mori. It is saved in this browser or device and sent to your chat server only when you send a message.'),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: !showKey,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Groq API key',
                  hintText: 'gsk_…',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: showKey ? 'Hide key' : 'Show key',
                    onPressed: () => setDialogState(() => showKey = !showKey),
                    icon: Icon(showKey ? Icons.visibility_off : Icons.visibility),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text('Leave blank to use the key configured on the server.', style: TextStyle(fontSize: 12, color: muted)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('groq_api_key');
                if (mounted) setState(() => _groqApiKey = null);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Clear'),
            ),
            FilledButton(
              onPressed: () async {
                final key = controller.text.trim();
                final prefs = await SharedPreferences.getInstance();
                if (key.isEmpty) {
                  await prefs.remove('groq_api_key');
                } else {
                  await prefs.setString('groq_api_key', key);
                }
                if (mounted) setState(() => _groqApiKey = key.isEmpty ? null : key);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? suggested]) async {
    final text = (suggested ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _messages.add(ChatMessage(text, fromUser: true, time: _now()));
      _sending = true;
      _input.clear();
    });
    _jumpToBottom();
    try {
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/chat'),
            headers: {
              'Content-Type': 'application/json',
              if (_groqApiKey != null && _groqApiKey!.isNotEmpty)
                'X-Groq-Api-Key': _groqApiKey!,
            },
            body: jsonEncode({'message': text}),
          )
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(data['detail'] ?? 'The assistant could not reply.');
      }
      setState(
        () => _messages.add(
          ChatMessage(
            data['reply'] as String? ?? 'I could not form a reply just now.',
            fromUser: false,
            time: _now(),
          ),
        ),
      );
    } on http.ClientException catch (error) {
      setState(
        () => _messages.add(
          ChatMessage(
            'Could not connect to the Mori API at $_apiBaseUrl. Start the API server and try again. (${error.message})',
            fromUser: false,
          ),
        ),
      );
    } on FormatException {
      setState(
        () => _messages.add(
          const ChatMessage('The Mori API returned an unreadable response. Check that the API is running at the configured URL.', fromUser: false),
        ),
      );
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(
        () => _messages.add(ChatMessage(message, fromUser: false)),
      );
    } finally {
      setState(() => _sending = false);
      _jumpToBottom();
    }
  }

  String _now() {
    final now = TimeOfDay.now();
    final hour = now.hourOfPeriod == 0 ? 12 : now.hourOfPeriod;
    return '$hour:${now.minute.toString().padLeft(2, '0')} ${now.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  void _jumpToBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final hasMessages = _messages.isNotEmpty;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    children: [
                      Expanded(
                        child: hasMessages ? _conversation() : _welcome(),
                      ),
                      _composer(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                        child: Text(
                          'Mori can make mistakes. Take what feels useful.',
                          style: TextStyle(
                            fontSize: 10,
                            color: ink.withValues(alpha: .45),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Container(
    padding: const EdgeInsets.fromLTRB(22, 15, 22, 14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .68),
      border: Border(bottom: BorderSide(color: ink.withValues(alpha: .07))),
    ),
    child: Row(
      children: [
        Container(
          width: 43,
          height: 43,
          decoration: BoxDecoration(
            color: const Color(0xFFE5EDE6),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(Icons.spa_rounded, color: forest, size: 23),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'mori',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: ink,
                  letterSpacing: -.5,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF58A879),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'HERE WITH YOU',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.3,
                      fontWeight: FontWeight.w600,
                      color: muted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'New conversation',
          onPressed: () => setState(_messages.clear),
          icon: const Icon(Icons.add_comment_outlined, color: muted, size: 21),
        ),
        const SizedBox(width: 3),
        IconButton(
          tooltip: 'Settings',
          onPressed: _openSettings,
          icon: const Icon(Icons.settings_outlined, color: muted, size: 21),
        ),
        const SizedBox(width: 3),
        CircleAvatar(
          radius: 18,
          backgroundColor: const Color(0xFFECE9DD),
          child: Text(
            'S',
            style: TextStyle(
              color: ink.withValues(alpha: .72),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _welcome() => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxHeight < 610;
      final horizontal = constraints.maxWidth > 650;
      return SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: horizontal ? 34 : 22,
          vertical: compact ? 20 : 34,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 740),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _hero(horizontal: horizontal, compact: compact),
                SizedBox(height: compact ? 22 : 30),
                Row(
                  children: [
                    const Text(
                      'START WHERE YOU ARE',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700,
                        color: muted,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'A few ideas for today',
                      style: TextStyle(
                        fontSize: 11,
                        color: ink.withValues(alpha: .48),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 13),
                if (horizontal)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _prompt(
                          'Mind dump',
                          'I have a lot on my mind',
                          'Let it out, one thought at a time.',
                          Icons.cloud_outlined,
                          const Color(0xFFE6EEE4),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _prompt(
                          'Find focus',
                          'Help me plan my day',
                          'Make room for what matters.',
                          Icons.wb_sunny_outlined,
                          const Color(0xFFF1EBD9),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _prompt(
                          'Small steps',
                          'I want to build a new habit',
                          'Start gently. Keep it doable.',
                          Icons.spa_outlined,
                          const Color(0xFFECE6EF),
                        ),
                      ),
                    ],
                  )
                else ...[
                  _prompt(
                    'Mind dump',
                    'I have a lot on my mind',
                    'Let it out, one thought at a time.',
                    Icons.cloud_outlined,
                    const Color(0xFFE6EEE4),
                  ),
                  const SizedBox(height: 10),
                  _prompt(
                    'Find focus',
                    'Help me plan my day',
                    'Make room for what matters.',
                    Icons.wb_sunny_outlined,
                    const Color(0xFFF1EBD9),
                  ),
                  const SizedBox(height: 10),
                  _prompt(
                    'Small steps',
                    'I want to build a new habit',
                    'Start gently. Keep it doable.',
                    Icons.spa_outlined,
                    const Color(0xFFECE6EF),
                  ),
                ],
                SizedBox(height: compact ? 16 : 24),
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 13,
                        color: ink.withValues(alpha: .4),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Your thoughts stay yours. Start with anything.',
                        style: TextStyle(
                          fontSize: 11,
                          color: ink.withValues(alpha: .5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _hero({required bool horizontal, required bool compact}) => Container(
    padding: EdgeInsets.fromLTRB(
      horizontal ? 28 : 23,
      compact ? 22 : 27,
      20,
      compact ? 20 : 25,
    ),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(25),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF274D3B), Color(0xFF183628)],
      ),
      boxShadow: [
        BoxShadow(
          color: forest.withValues(alpha: .18),
          blurRadius: 24,
          offset: const Offset(0, 11),
        ),
      ],
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .11),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 12,
                      color: Color(0xFFC6D7A7),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'YOUR DAILY PAUSE',
                      style: TextStyle(
                        fontSize: 9,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFDCE7D3),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: compact ? 13 : 19),
              Text(
                'A little space\nto think clearly.',
                style: TextStyle(
                  fontSize: horizontal ? 32 : 30,
                  height: 1.13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1.05,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Take a breath. We can untangle it together.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: Color(0xFFD0DDD1),
                ),
              ),
            ],
          ),
        ),
        if (horizontal) ...[
          const SizedBox(width: 8),
          _heroArt(size: compact ? 100 : 132),
        ],
      ],
    ),
  );

  Widget _heroArt({required double size}) => SizedBox(
    width: size,
    height: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .08),
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: size * .72,
          height: size * .72,
          decoration: BoxDecoration(
            color: const Color(0xFF9EB88B).withValues(alpha: .2),
            shape: BoxShape.circle,
          ),
        ),
        Icon(
          Icons.spa_rounded,
          size: size * .42,
          color: const Color(0xFFDDE7BC),
        ),
        Positioned(
          right: size * .12,
          top: size * .13,
          child: Icon(
            Icons.auto_awesome,
            size: size * .13,
            color: const Color(0xFFE9D99A),
          ),
        ),
        Positioned(
          left: size * .12,
          bottom: size * .16,
          child: Icon(
            Icons.circle,
            size: size * .06,
            color: const Color(0xFFE9D99A),
          ),
        ),
      ],
    ),
  );

  Widget _prompt(
    String label,
    String text,
    String subtitle,
    IconData icon,
    Color tint,
  ) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(17),
    child: InkWell(
      borderRadius: BorderRadius.circular(17),
      onTap: () => _send(text),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: ink.withValues(alpha: .07)),
          boxShadow: [
            BoxShadow(
              color: ink.withValues(alpha: .025),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, size: 20, color: forest),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 9,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                      color: muted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: ink.withValues(alpha: .53),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 5),
            Icon(
              Icons.arrow_forward_rounded,
              size: 16,
              color: ink.withValues(alpha: .38),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _conversation() => ListView.builder(
    controller: _scroll,
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
    itemCount: _messages.length + (_sending ? 1 : 0),
    itemBuilder: (context, index) {
      if (_sending && index == _messages.length) return _typing();
      final message = _messages[index];
      return _bubble(message);
    },
  );

  Widget _bubble(ChatMessage message) => Align(
    alignment: message.fromUser ? Alignment.centerRight : Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 17),
      child: Column(
        crossAxisAlignment: message.fromUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (!message.fromUser)
            const Padding(
              padding: EdgeInsets.only(left: 3, bottom: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.spa_rounded, color: forest, size: 13),
                  SizedBox(width: 5),
                  Text(
                    'mori',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      color: forest,
                    ),
                  ),
                ],
              ),
            ),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * .78,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: message.fromUser ? forest : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(message.fromUser ? 18 : 5),
                bottomRight: Radius.circular(message.fromUser ? 5 : 18),
              ),
              border: message.fromUser
                  ? null
                  : Border.all(color: ink.withValues(alpha: .055)),
            ),
            child: Text(
              message.text,
              style: TextStyle(
                fontSize: 14,
                height: 1.55,
                color: message.fromUser ? Colors.white : ink,
              ),
            ),
          ),
          if (message.time != null)
            Padding(
              padding: const EdgeInsets.only(top: 5, left: 3, right: 3),
              child: Text(
                message.time!,
                style: const TextStyle(fontSize: 10, color: muted),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _typing() => const Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: EdgeInsets.only(left: 3, bottom: 17),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.spa_rounded, color: forest, size: 14),
          SizedBox(width: 9),
          Text(
            'Mori is thinking…',
            style: TextStyle(
              color: muted,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _composer() => Container(
    margin: const EdgeInsets.fromLTRB(15, 7, 15, 0),
    padding: const EdgeInsets.fromLTRB(14, 7, 7, 7),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(21),
      border: Border.all(color: ink.withValues(alpha: .09)),
      boxShadow: [
        BoxShadow(
          color: ink.withValues(alpha: .04),
          blurRadius: 18,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _input,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _send(),
            decoration: const InputDecoration(
              hintText: 'Share what’s on your mind…',
              hintStyle: TextStyle(color: Color(0xFF9AA39D), fontSize: 13),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 3, vertical: 11),
            ),
          ),
        ),
        const SizedBox(width: 5),
        Material(
          color: forest,
          borderRadius: BorderRadius.circular(15),
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: _sending ? null : () => _send(),
            child: SizedBox(
              width: 43,
              height: 43,
              child: Icon(
                _sending
                    ? Icons.more_horiz_rounded
                    : Icons.arrow_upward_rounded,
                color: Colors.white,
                size: 21,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
