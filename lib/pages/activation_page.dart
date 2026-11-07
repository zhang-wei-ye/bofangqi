import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../license.dart';
import 'home_shell.dart';

/// 启动入口：先校验本机激活码，有效才进主界面，否则显示激活页。
class LicenseGate extends StatefulWidget {
  const LicenseGate({super.key});

  @override
  State<LicenseGate> createState() => _LicenseGateState();
}

class _LicenseGateState extends State<LicenseGate> {
  LicenseState? _state;

  @override
  void initState() {
    super.initState();
    LicenseStore.check().then((s) {
      if (mounted) setState(() => _state = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    if (s == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (s.ok) return const HomeShell();
    return ActivationPage(previous: s, onActivated: (s) => setState(() => _state = s));
  }
}

/// 激活页：显示本机指纹，输入作者给的激活码。
class ActivationPage extends StatefulWidget {
  /// 启动时的检查结果，用来提示「已过期」等情况。
  final LicenseState previous;
  final ValueChanged<LicenseState> onActivated;

  const ActivationPage({super.key, required this.previous, required this.onActivated});

  @override
  State<ActivationPage> createState() => _ActivationPageState();
}

class _ActivationPageState extends State<ActivationPage> {
  final _code = TextEditingController();
  String? _fingerprint;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    LicenseStore.fingerprint().then((fp) {
      if (mounted) setState(() => _fingerprint = fp);
    });
    _error = switch (widget.previous.status) {
      LicenseStatus.expired => '授权已于 ${_date(widget.previous.expiresAt!)} 到期，请重新获取激活码',
      LicenseStatus.invalid => '本机保存的激活码无效，请重新激活',
      _ => null,
    };
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _copyFingerprint() async {
    final fp = _fingerprint;
    if (fp == null) return;
    await Clipboard.setData(ClipboardData(text: fp));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('指纹已复制')));
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) setState(() => _code.text = text);
  }

  Future<void> _activate() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = '请输入激活码');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final s = await LicenseStore.activate(code);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (s.status) {
      case LicenseStatus.valid:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.expiresAt == null ? '激活成功（永久）' : '激活成功，有效期至 ${_date(s.expiresAt!)}')),
        );
        widget.onActivated(s);
      case LicenseStatus.expired:
        setState(() => _error = '该激活码已于 ${_date(s.expiresAt!)} 到期');
      case LicenseStatus.invalid || LicenseStatus.missing:
        setState(() => _error = '激活码无效，请确认复制完整，且是用本机指纹申请的');
    }
  }

  static String _date(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('激活竹林影馆')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: ListTile(
                title: _fingerprint == null
                    ? const Text('正在读取…')
                    : SelectableText(
                        _fingerprint!,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 18, letterSpacing: 1),
                      ),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: '复制指纹',
                  onPressed: _fingerprint == null ? null : _copyFingerprint,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('激活码：', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _code,
              minLines: 3,
              maxLines: 5,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: '粘贴激活码',
                suffixIcon: IconButton(icon: const Icon(Icons.content_paste), tooltip: '粘贴', onPressed: _paste),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _activate,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('激活'),
            ),
          ],
        ),
      ),
    );
  }
}
