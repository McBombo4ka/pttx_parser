import 'package:flutter/material.dart';

import 'ar_view_screen.dart';
import 'model_loader_service.dart';
import 'model_source.dart';

/// Режим работы экрана выбора модели.
enum _PickerMode {
  /// Открывает AR-вьювер напрямую.
  standalone,

  /// Возвращает выбранную модель через [Navigator.pop] для прикрепления к слайду.
  attachment,
}

/// Экран выбора 3D-модели.
///
/// В режиме **standalone** (по умолчанию) кнопка «Показать» открывает AR.
///
/// В режиме **attachment** (когда передан [attachToSlideIndex]) кнопка
/// «Прикрепить к слайду N» возвращает [ModelSource] через [Navigator.pop].
/// Пользователь также может предварительно посмотреть модель в AR.
class ModelPickerScreen extends StatefulWidget {
  /// Если задан — экран работает в режиме прикрепления к этому слайду (0-based).
  final int? attachToSlideIndex;

  const ModelPickerScreen({super.key, this.attachToSlideIndex});

  @override
  State<ModelPickerScreen> createState() => _ModelPickerScreenState();
}

class _ModelPickerScreenState extends State<ModelPickerScreen> {
  final _loaderService = ModelLoaderService();
  final _urlController = TextEditingController();

  ModelSource? _selectedModel;
  bool _isLoading = false;
  String? _errorMessage;

  _PickerMode get _mode => widget.attachToSlideIndex != null
      ? _PickerMode.attachment
      : _PickerMode.standalone;

  bool get _isAttachMode => _mode == _PickerMode.attachment;

  // Номер слайда для отображения в UI (1-based)
  int get _slideNumber => (widget.attachToSlideIndex ?? 0) + 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildContent(),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: Text(
        _isAttachMode ? 'Модель для слайда $_slideNumber' : 'AR Viewer',
      ),
      centerTitle: true,
      backgroundColor: Theme.of(context).colorScheme.inversePrimary,
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_isAttachMode) ...[
            _buildAttachmentBanner(),
            const SizedBox(height: 20),
          ],
          const SizedBox(height: 8),
          _buildFileSection(),
          const SizedBox(height: 28),
          _buildDivider(),
          const SizedBox(height: 28),
          _buildUrlSection(),
          const SizedBox(height: 32),
          if (_selectedModel != null) ...[
            _buildSelectedModelCard(),
            const SizedBox(height: 20),
          ],
          if (_errorMessage != null) ...[
            _buildErrorCard(),
            const SizedBox(height: 20),
          ],
          _buildPrimaryButton(),
          if (_isAttachMode && _selectedModel != null) ...[
            const SizedBox(height: 12),
            _buildPreviewButton(),
          ],
          const SizedBox(height: 16),
          _buildSupportedFormatsNote(),
        ],
      ),
    );
  }

  // ── Секции ──────────────────────────────────────────────────────────────────

  Widget _buildAttachmentBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.link, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Выберите модель и прикрепите её к слайду $_slideNumber.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(
          icon: Icons.folder_open,
          label: 'Загрузить из файлов устройства',
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _pickFile,
          icon: const Icon(Icons.upload_file),
          label: const Text('Выбрать файл'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }

  Widget _buildUrlSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel(icon: Icons.link, label: 'Загрузить по URL'),
        const SizedBox(height: 12),
        TextField(
          controller: _urlController,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: 'https://example.com/model.glb',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.public),
            suffixIcon: _urlController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _urlController.clear();
                      setState(() {});
                    },
                  )
                : null,
          ),
          onChanged: (_) => setState(() => _errorMessage = null),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _loadFromUrl,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Использовать этот URL'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }

  // ── Кнопки действий ─────────────────────────────────────────────────────────

  /// Главная кнопка: «Прикрепить» или «Показать» в зависимости от режима.
  Widget _buildPrimaryButton() {
    final isEnabled = _selectedModel != null;

    if (_isAttachMode) {
      return FilledButton.icon(
        onPressed: isEnabled ? _attachAndReturn : null,
        icon: const Icon(Icons.link),
        label: Text(
          'Прикрепить к слайду $_slideNumber',
          style: const TextStyle(fontSize: 15),
        ),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }

    return FilledButton.icon(
      onPressed: isEnabled ? _openArView : null,
      icon: const Icon(Icons.camera_alt),
      label: const Text('Показать', style: TextStyle(fontSize: 16)),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  /// В режиме прикрепления — кнопка предпросмотра в AR без сохранения.
  Widget _buildPreviewButton() {
    return OutlinedButton.icon(
      onPressed: _openArView,
      icon: const Icon(Icons.camera_alt_outlined),
      label: const Text('Предпросмотр в AR'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  // ── Вспомогательные виджеты ─────────────────────────────────────────────────

  Widget _buildSectionLabel({required IconData icon, required String label}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'или',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }

  Widget _buildSelectedModelCard() {
    final model = _selectedModel!;
    return Card(
      color: Colors.green.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green.shade100,
          child: const Icon(Icons.view_in_ar, color: Colors.green),
        ),
        title: Text(
          model.displayName,
          style: const TextStyle(fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${model.formatLabel} · ${model.isRemote ? 'URL' : 'Локальный файл'}',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.close, color: Colors.grey),
          tooltip: 'Убрать выбор',
          onPressed: () => setState(() => _selectedModel = null),
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(color: Colors.red.shade800, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportedFormatsNote() {
    return Center(
      child: Text(
        'Форматы: ${ModelSource.supportedExtensions.map((e) => '.$e').join('  ')}',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Colors.grey),
      ),
    );
  }

  // ── Действия ────────────────────────────────────────────────────────────────

  Future<void> _pickFile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _loaderService.pickFromStorage();

    setState(() {
      _isLoading = false;
      switch (result) {
        case ModelLoadSuccess(:final source):
          _selectedModel = source;
          _errorMessage = null;
        case ModelLoadFailure(:final message):
          _errorMessage = message;
        case ModelLoadCancelled():
          break;
      }
    });
  }

  void _loadFromUrl() {
    setState(() => _errorMessage = null);

    final result = _loaderService.createFromUrl(_urlController.text);

    setState(() {
      switch (result) {
        case ModelLoadSuccess(:final source):
          _selectedModel = source;
          _errorMessage = null;
          FocusScope.of(context).unfocus();
        case ModelLoadFailure(:final message):
          _errorMessage = message;
        case ModelLoadCancelled():
          break;
      }
    });
  }

  void _openArView() {
    if (_selectedModel == null) return;
    Future.delayed(const Duration(milliseconds: 300));
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ArViewScreen(modelSource: _selectedModel!),
      ),
    );
  }

  /// Возвращает [ModelSource] в вызывающий экран через Navigator.pop.
  void _attachAndReturn() {
    if (_selectedModel == null) return;
    Navigator.of(context).pop(_selectedModel);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }
}