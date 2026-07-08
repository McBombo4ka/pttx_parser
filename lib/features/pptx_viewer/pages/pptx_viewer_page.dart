import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../ar_core/ar_model_repository.dart';
import '../../../ar_core/ar_view_screen.dart';
import '../../../ar_core/donload.dart';
import '../../../ar_core/model_picker_screen.dart';
import '../../../ar_core/model_source.dart';
import '../../../ar_core/pptx_parser.dart';
import '../../../ar_core/slide_models.dart';
import '../../../core/network/presentation_web_server.dart';
import '../../../editor/edit_models.dart';
import '../../../editor/edit_screen.dart';
import '../../../exporter/html_exporter.dart';
import '../widgets/slide_canvas.dart';

class PptxViewerPage extends StatefulWidget {
  final PresentationWebServer webServer;
  const PptxViewerPage({super.key, required this.webServer});

  @override
  State<PptxViewerPage> createState() => _PptxViewerPageState();
}

class _PptxViewerPageState extends State<PptxViewerPage> {
  PptxPresentation? _presentation;
  int _index = 0;
  bool _loading = true;
  String? _errorText;

  final _arRepository = ArModelRepository(presentationKey: 'test');

  @override
  void initState() {
    super.initState();
    widget.webServer.addListener(_onServerIndexChanged);
    _initAsync();
  }

  void _onServerIndexChanged() {
    if (!mounted) return;
    final serverIndex = widget.webServer.currentSlideIndex;
    if (serverIndex != _index) setState(() => _index = serverIndex);
  }

  Future<void> _initAsync() async {
    await Future.wait([_loadPresentation(), _arRepository.load()]);
  }

  Future<void> _loadPresentation() async {
    try {
      final data = await rootBundle.load('assets/test.pptx');
      final bytes = data.buffer.asUint8List();
      final result = await parsePptxFile(bytes);
      if (!mounted) return;
      setState(() {
        _presentation = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorText = e.toString();
      });
    }
  }

  void _gotoSlide(int index) {
    if (_presentation == null) return;
    widget.webServer.gotoSlide(
      index.clamp(0, _presentation!.slides.length - 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_presentation == null) {
      return Scaffold(
        body: Center(child: Text(_errorText ?? 'Не удалось загрузить PPTX')),
      );
    }

    final slide = _presentation!.slides[_index];

    return ListenableBuilder(
      listenable: _arRepository,
      builder: (context, _) => Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: AspectRatio(
              aspectRatio: _presentation!.slideSize.aspectRatio,
              child: GestureDetector(
                onHorizontalDragEnd: _onHorizontalSwipe,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: _presentation!.slideSize.widthPx,
                    height: _presentation!.slideSize.heightPx,
                    child: SlideCanvas(slide: slide, theme: _presentation!.theme),
                  ),
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: _buildControls(),
      ),
    );
  }

  Widget _buildControls() {
    final total = _presentation?.slides.length ?? 0;
    final attachedModel = _arRepository.getModel(_index);

    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _index > 0 ? () => _gotoSlide(_index - 1) : null,
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Редактировать слайд',
            onPressed: _presentation == null
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => EditScreen(initialSlideIndex: _index),
                    )),
          ),
          Text('${_index + 1} / $total'),
          IconButton(
            icon: Icon(
              Icons.link,
              color: attachedModel != null
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: attachedModel != null ? 'Изменить AR-модель' : 'Прикрепить AR-модель',
            onPressed: _openArModelPicker,
          ),
          // Кнопка AR — открывает камеру на телефоне и 3D-модель в браузере.
          IconButton(
            icon: Icon(
              Icons.view_in_ar,
              color: attachedModel != null
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: attachedModel == null
                ? 'Сначала прикрепите 3D-модель'
                : 'Показать: ${attachedModel.displayName}',
            onPressed: attachedModel != null ? () => _openArView(attachedModel) : null,
          ),
          IconButton(
            icon: const Icon(Icons.code),
            tooltip: 'Экспорт HTML',
            onPressed: _presentation == null ? null : _exportHtml,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: _index < total - 1 ? () => _gotoSlide(_index + 1) : null,
          ),
        ],
      ),
    );
  }

  void _onHorizontalSwipe(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    if (v < 0) _gotoSlide(_index + 1);
    if (v > 0) _gotoSlide(_index - 1);
  }

  Future<void> _openArModelPicker() async {
    final result = await Navigator.of(context).push<ModelSource>(
      MaterialPageRoute(
        builder: (_) => ModelPickerScreen(attachToSlideIndex: _index),
      ),
    );
    if (result == null || !mounted) return;
    await _arRepository.attachModel(_index, result);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Модель «${result.displayName}» прикреплена к слайду ${_index + 1}.'),
      duration: const Duration(seconds: 3),
    ));
  }

  /// Открывает AR на телефоне и уведомляет браузер.
  /// После возврата — уведомляет браузер о закрытии AR.
  Future<void> _openArView(ModelSource model) async {
    // Уведомляем браузер: показать 3D-модель.
    widget.webServer.startArMode(model);

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ArViewScreen(modelSource: model)),
    );

    // Пользователь вернулся с AR-экрана — возвращаем браузер к презентации.
    widget.webServer.stopArMode();
  }

  Future<void> _exportHtml() async {
    final model = context.read<PresentationEditModel>();
    final html = HtmlExporter(model).export();
    try {
      await DownloadsSaver.saveHtml(fileName: 'presentation.html', html: html);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сохранено в Downloads')),
      );
    } catch (e) {
      debugPrint('EXPORT ERROR: $e');
    }
  }

  @override
  void dispose() {
    widget.webServer.removeListener(_onServerIndexChanged);
    super.dispose();
  }
}