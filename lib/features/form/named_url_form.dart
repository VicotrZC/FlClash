import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';

import 'batch_section.dart';
import 'form_page.dart';
import 'form_row.dart';

typedef NamedUrl = ({
  String label,
  String url,
  String ageSecretKey,
  String userAgent,
  String customHeaders,
});

Future<NamedUrl?> showNamedUrlForm(
  BuildContext context, {
  required String title,
  String label = '',
  String url = '',
  FormFieldValidator<String>? labelValidator,
  FormFieldValidator<String>? urlValidator,
  bool withSubscriptionOptions = false,
}) async {
  final res = await showFormSheet<List<NamedUrl>>(
    context: context,
    builder: (_) => NamedUrlForm(
      title: title,
      label: label,
      url: url,
      labelValidator: labelValidator,
      urlValidator: urlValidator,
      withSubscriptionOptions: withSubscriptionOptions,
    ),
  );
  return res?.single;
}

/// A batch skips the urls in [existingUrls].
Future<List<NamedUrl>?> showNamedUrlsForm(
  BuildContext context, {
  required String title,
  String? urlLabel,
  String? batchTip,
  FormFieldValidator<String>? labelValidator,
  FormFieldValidator<String>? urlValidator,
  Set<String> existingUrls = const {},
  bool withAgeSecretKey = false,
  bool withSubscriptionOptions = false,
}) {
  return showFormSheet<List<NamedUrl>>(
    context: context,
    builder: (_) => NamedUrlForm(
      title: title,
      urlLabel: urlLabel,
      batchTip: batchTip,
      labelValidator: labelValidator,
      urlValidator: urlValidator,
      batch: true,
      existingUrls: existingUrls,
      withAgeSecretKey: withAgeSecretKey,
      withSubscriptionOptions: withSubscriptionOptions,
    ),
  );
}

enum _NamedUrlField { label, url, customHeaders }

/// The url below the name holds the focus, as the one field that must be filled.
/// Pops a list so a single url and a batch return through the same path.
class NamedUrlForm extends StatefulWidget {
  final String title;
  final String label;
  final String url;
  final String? urlLabel;
  final String? batchTip;
  final FormFieldValidator<String>? labelValidator;
  final FormFieldValidator<String>? urlValidator;
  final bool batch;
  final Set<String> existingUrls;
  final bool withAgeSecretKey;
  final bool withSubscriptionOptions;

  const NamedUrlForm({
    super.key,
    required this.title,
    this.label = '',
    this.url = '',
    this.urlLabel,
    this.batchTip,
    this.labelValidator,
    this.urlValidator,
    this.batch = false,
    this.existingUrls = const {},
    this.withAgeSecretKey = false,
    this.withSubscriptionOptions = false,
  });

  @override
  State<NamedUrlForm> createState() => _NamedUrlFormState();
}

class _NamedUrlFormState extends State<NamedUrlForm> {
  final _urlFocusNode = FocusNode();
  final _ageSecretKeyFocusNode = FocusNode();
  late final TextEditingController _labelController;
  late final TextEditingController _urlController;
  final _ageSecretKeyController = TextEditingController();
  final _batchController = TextEditingController();
  final _userAgentController = TextEditingController();
  final _customHeadersController = TextEditingController();
  bool _isBatch = false;
  bool _showAdvanced = false;
  bool _attempted = false;
  ParsedInput<String>? _parsed;

  String get _urlLabel => widget.urlLabel ?? context.appLocalizations.url;

  BatchInput<String> get _batchInput {
    final appLocalizations = context.appLocalizations;
    return BatchInput(
      label: _urlLabel,
      formatTip: widget.batchTip ?? appLocalizations.batchUrlInputTip,
      parse: (text) => parseUrlInput(
        text,
        isValid: (url) => _validateBatchUrl(url) == null,
        existing: widget.existingUrls,
      ),
      issueMessage: (issue) => _validateBatchUrl(issue.raw)!,
    );
  }

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.label);
    _urlController = TextEditingController(text: widget.url);
  }

  @override
  void dispose() {
    _urlFocusNode.dispose();
    _ageSecretKeyFocusNode.dispose();
    _labelController.dispose();
    _urlController.dispose();
    _ageSecretKeyController.dispose();
    _batchController.dispose();
    _userAgentController.dispose();
    _customHeadersController.dispose();
    super.dispose();
  }

  String? _validateUrl(String? value) {
    final validator = widget.urlValidator;
    if (validator != null) {
      return validator(value);
    }
    final appLocalizations = context.appLocalizations;
    final url = value?.trim() ?? '';
    if (url.isEmpty) {
      return appLocalizations.emptyTip(_urlLabel);
    }
    if (!url.isUrl) {
      return appLocalizations.urlTip(_urlLabel);
    }
    return null;
  }

  String? _validateBatchUrl(String url) {
    if (url.length > TextInputLimits.url) {
      final appLocalizations = context.appLocalizations;
      return appLocalizations.maxLengthTip(_urlLabel, TextInputLimits.url);
    }
    return _validateUrl(url);
  }

  ({_NamedUrlField field, String message})? _issue() {
    final labelError = widget.labelValidator?.call(_labelController.text);
    if (labelError != null) {
      return (field: _NamedUrlField.label, message: labelError);
    }
    final urlError = _validateUrl(_urlController.text);
    if (urlError != null) {
      return (field: _NamedUrlField.url, message: urlError);
    }
    final headerError = _customHeadersError();
    if (headerError != null) {
      return (field: _NamedUrlField.customHeaders, message: headerError);
    }
    return null;
  }

  /// 校验自定义请求头，返回错误文案；全部合法时返回 null。
  ///
  /// 必须拦下来而不是交给 [CustomHeaders.parse] 静默跳过：被跳过的那一行
  /// 在保存后就没了，用户只会看到订阅 403，却看不出是自己写错了。
  String? _customHeadersError() {
    if (!widget.withSubscriptionOptions) {
      return null;
    }
    final line = CustomHeaders.firstInvalidLine(_customHeadersController.text);
    if (line == null) {
      return null;
    }
    return context.appLocalizations.customHeadersInvalid(line);
  }

  void _toggleBatch() {
    setState(() {
      _isBatch = !_isBatch;
      _attempted = false;
      if (_isBatch && _batchController.text.isEmpty) {
        _batchController.text = _urlController.text.trim();
      }
      if (_isBatch) {
        _parsed = _batchInput.parse(_batchController.text);
      }
    });
  }

  void _handleChanged(String _) {
    if (_attempted) {
      setState(() {});
    }
  }

  void _handleBatchChanged(String text) {
    setState(() {
      _parsed = _batchInput.parse(text);
    });
  }

  void _handleSubmit() {
    final userAgent = _userAgentController.text.trim();
    final customHeaders = _customHeadersController.text.trim();
    if (_isBatch) {
      final parsed = _parsed;
      if (_customHeadersError() != null ||
          parsed == null ||
          !parsed.isValid ||
          parsed.entries.isEmpty) {
        setState(() {
          _attempted = true;
          // 请求头报错时自动展开，否则错误藏在折叠区里，用户只看到一句
          // 「第 2 行格式不对」却找不到那个输入框。
          if (_customHeadersError() != null) {
            _showAdvanced = true;
          }
        });
        return;
      }
      // 批量导入只能填一套请求头，应用到这次导入的每个 URL 上。
      Navigator.of(context).pop<List<NamedUrl>>([
        for (final url in parsed.entries)
          (
            label: '',
            url: url,
            ageSecretKey: '',
            userAgent: userAgent,
            customHeaders: customHeaders,
          ),
      ]);
      return;
    }
    if (_issue() != null) {
      setState(() {
        _attempted = true;
        if (_customHeadersError() != null) {
          _showAdvanced = true;
        }
      });
      return;
    }
    Navigator.of(context).pop<List<NamedUrl>>([
      (
        label: _labelController.text.trim(),
        url: _urlController.text.trim(),
        ageSecretKey: _ageSecretKeyController.text.trim(),
        userAgent: userAgent,
        customHeaders: customHeaders,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final issue = _attempted && !_isBatch ? _issue() : null;
    // 批量模式下没有单条字段的 issue，但请求头同样要校验并回显；
    // 之前这里只走 batchInput.errorOf，输错的请求头永远不会被提示。
    final headerError = _attempted ? _customHeadersError() : null;
    final String? error;
    if (_isBatch) {
      error =
          headerError ??
          _batchInput.errorOf(appLocalizations, _parsed, attempted: _attempted);
    } else {
      error = issue?.message;
    }
    // 批量模式 issue 恒为 null，若只看 issue?.field，请求头报错时输入框不会标红。
    final headerInvalid =
        headerError != null || issue?.field == _NamedUrlField.customHeaders;
    return FormPage(
      title: _isBatch ? appLocalizations.batchImport : widget.title,
      saveLabel: appLocalizations.submit,
      onSave: _handleSubmit,
      error: error,
      actions: [
        if (widget.batch)
          IconButtonData(
            glyph: _isBatch ? AppGlyphs.textShort : AppGlyphs.listAdd,
            tooltip: _isBatch
                ? appLocalizations.singleImport
                : appLocalizations.batchImport,
            onPressed: _toggleBatch,
          ),
      ],
      children: [
        if (_isBatch)
          BatchSection(
            batch: _batchInput,
            controller: _batchController,
            parsed: _parsed,
            onChanged: _handleBatchChanged,
          )
        else
          _buildFields(appLocalizations, issue?.field),
        // 批量导入同样需要请求头：vpncheap 这类机场少一个 X-Client-Encrypt
        // 就是 403，不能要求用户导入完再逐个编辑。
        if (widget.withSubscriptionOptions)
          _buildSubscriptionOptions(appLocalizations, headerInvalid),
      ],
    );
  }

  Widget _buildFields(
    AppLocalizations appLocalizations,
    _NamedUrlField? invalid,
  ) {
    return generateSection(
      items: [
        FormRow(
          title: appLocalizations.name,
          invalid: invalid == _NamedUrlField.label,
          trailing: FormRowTextField(
            controller: _labelController,
            hintText: appLocalizations.optional,
            textInputAction: TextInputAction.next,
            inputFormatters: TextInputLimits.limit(TextInputLimits.name),
            onChanged: _handleChanged,
            onFieldSubmitted: (_) => _urlFocusNode.requestFocus(),
          ),
        ),
        FormRow(
          title: _urlLabel,
          invalid: invalid == _NamedUrlField.url,
          trailing: FormRowTextField(
            controller: _urlController,
            focusNode: _urlFocusNode,
            autofocus: true,
            hintText: appLocalizations.required,
            keyboardType: TextInputType.url,
            textInputAction: widget.withAgeSecretKey
                ? TextInputAction.next
                : TextInputAction.done,
            autocorrect: false,
            inputFormatters: TextInputLimits.limit(TextInputLimits.url),
            onChanged: _handleChanged,
            onFieldSubmitted: (_) {
              if (widget.withAgeSecretKey) {
                _ageSecretKeyFocusNode.requestFocus();
              } else {
                _handleSubmit();
              }
            },
          ),
        ),
        if (widget.withAgeSecretKey)
          FormRow(
            title: appLocalizations.ageSecretKey,
            trailing: FormRowSecretTextField(
              controller: _ageSecretKeyController,
              focusNode: _ageSecretKeyFocusNode,
              hintText: appLocalizations.optional,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _handleSubmit(),
            ),
          ),
      ],
    );
  }

  /// 「订阅高级选项」：每个订阅自己的 User-Agent 与请求头。
  ///
  /// 单条导入与批量导入都会渲染这一块；批量时这套值应用到本次导入的每个 URL。
  ///
  /// [headerInvalid] 用 bool 而不是字段枚举：批量模式下没有单条 issue，
  /// 只看枚举的话请求头报错时输入框永远不会标红。
  Widget _buildSubscriptionOptions(
    AppLocalizations appLocalizations,
    bool headerInvalid,
  ) {
    return generateSection(
      items: [
        FormRow(
          title: appLocalizations.subscriptionAdvanced,
          onPressed: () {
            setState(() {
              _showAdvanced = !_showAdvanced;
            });
          },
          trailing: IconButton(
            tooltip: _showAdvanced
                ? appLocalizations.showLess
                : appLocalizations.showMore,
            onPressed: () {
              setState(() {
                _showAdvanced = !_showAdvanced;
              });
            },
            icon: GlyphIcon(
              _showAdvanced ? AppGlyphs.chevronUp : AppGlyphs.chevronDown,
              size: 18,
            ),
          ),
        ),
        if (_showAdvanced) ...[
          FormRow(
            title: appLocalizations.userAgent,
            trailing: FormRowTextField(
              controller: _userAgentController,
              hintText: appLocalizations.optional,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              inputFormatters: TextInputLimits.limit(TextInputLimits.name),
            ),
          ),
          FormRow(
            title: appLocalizations.customHeaders,
            invalid: headerInvalid,
            trailing: MultiLineHeaderField(
              controller: _customHeadersController,
              hintText: appLocalizations.customHeadersTip,
              onChanged: _handleChanged,
            ),
          ),
        ],
      ],
    );
  }
}

/// 自定义请求头是多行文本，而 FormRowTextField 只支持单行。
class MultiLineHeaderField extends StatelessWidget {
  const MultiLineHeaderField({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.multiline,
      minLines: 3,
      maxLines: 6,
      autocorrect: false,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        isDense: true,
        border: InputBorder.none,
      ),
    );
  }
}
