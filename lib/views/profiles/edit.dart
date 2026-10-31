import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/form/form.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/pages/editor.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _ProfileField { label, url, autoUpdateInterval, customHeaders }

class EditProfileView extends ConsumerStatefulWidget {
  final Profile profile;

  const EditProfileView({super.key, required this.profile});

  @override
  ConsumerState<EditProfileView> createState() => _EditProfileViewState();
}

class _EditProfileViewState extends ConsumerState<EditProfileView> {
  late final TextEditingController _labelController;
  late final TextEditingController _urlController;
  late final TextEditingController _ageSecretKeyController;
  late final TextEditingController _userAgentController;
  late final TextEditingController _customHeadersController;
  late final TextEditingController _autoUpdateDurationController;
  late bool _autoUpdate;
  bool _showAdvanced = false;
  Uint8List? _editedData;
  bool _attempted = false;
  final _fileInfoNotifier = ValueNotifier<FileInfo?>(null);
  late SetupAction _setupAction;
  Uint8List? _fileData;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.profile.label);
    _urlController = TextEditingController(text: widget.profile.url);
    _ageSecretKeyController = TextEditingController(
      text: widget.profile.ageSecretKey,
    );
    _userAgentController = TextEditingController(
      text: widget.profile.userAgent ?? '',
    );
    _customHeadersController = TextEditingController(
      text: CustomHeaders.format(widget.profile.customHeaders),
    );
    _showAdvanced =
        widget.profile.userAgent != null ||
        widget.profile.customHeaders.isNotEmpty;
    _autoUpdate = widget.profile.autoUpdate;
    _autoUpdateDurationController = TextEditingController(
      text: widget.profile.autoUpdateDuration.inMinutes.toString(),
    );
    _setupAction = ref.read(setupActionProvider.notifier);
    _updateFileInfo();
  }

  Future<void> _updateFileInfo() async {
    final file = await widget.profile.file;
    final fileInfo = await file.getFileInfo();
    if (!mounted) {
      return;
    }
    _fileInfoNotifier.value = fileInfo;
  }

  ({_ProfileField field, String message})? _issue(
    AppLocalizations appLocalizations,
  ) {
    final labelError = validateProfileName(
      appLocalizations,
      _labelController.text,
    );
    if (labelError != null) {
      return (field: _ProfileField.label, message: labelError);
    }
    if (widget.profile.type != ProfileType.url) {
      return null;
    }
    final url = _urlController.text;
    if (url.isEmpty) {
      return (
        field: _ProfileField.url,
        message: appLocalizations.profileUrlNullValidationDesc,
      );
    }
    if (!url.isUrl) {
      return (
        field: _ProfileField.url,
        message: appLocalizations.profileUrlInvalidValidationDesc,
      );
    }
    // 请求头必须在这里拦下：保存时用的是 CustomHeaders.parse，它会把非法行
    // 静默丢掉，用户只会看到订阅 403，却看不出是自己写错了。
    //
    // 位置很关键：必须排在下面 `if (!_autoUpdate) return null;` 之前。
    // 否则关掉自动更新的用户会整个绕过校验 —— 而请求头与自动更新无关。
    final headerLine = CustomHeaders.firstInvalidLine(
      _customHeadersController.text,
    );
    if (headerLine != null) {
      return (
        field: _ProfileField.customHeaders,
        message: appLocalizations.customHeadersInvalid(headerLine),
      );
    }
    if (!_autoUpdate) {
      return null;
    }
    final interval = _autoUpdateDurationController.text;
    if (interval.isEmpty) {
      return (
        field: _ProfileField.autoUpdateInterval,
        message: appLocalizations.profileAutoUpdateIntervalNullValidationDesc,
      );
    }
    if ((int.tryParse(interval) ?? 0) <= 0) {
      return (
        field: _ProfileField.autoUpdateInterval,
        message:
            appLocalizations.profileAutoUpdateIntervalInvalidValidationDesc,
      );
    }
    return null;
  }

  void _handleChanged(String _) {
    if (_attempted) {
      setState(() {});
    }
  }

  Future<void> _handleConfirm() async {
    final issue = _issue(context.appLocalizations);
    if (issue != null) {
      setState(() {
        _attempted = true;
        // 请求头报错时把高级选项展开，否则错误指向一个看不见的输入框。
        // 导入页已经这么做了，这里之前漏掉，用户只看到一句「第 N 行格式不对」。
        if (issue.field == _ProfileField.customHeaders) {
          _showAdvanced = true;
        }
      });
      return;
    }
    final current =
        ref.read(profilesProvider).getProfile(widget.profile.id) ??
        widget.profile;
    final interval = int.tryParse(_autoUpdateDurationController.text);
    var profile = current.copyWith(
      url: _urlController.text,
      ageSecretKey: _ageSecretKeyController.text.trim(),
      userAgent: _userAgentController.text.trim().isEmpty
          ? null
          : _userAgentController.text.trim(),
      customHeaders: CustomHeaders.parse(_customHeadersController.text),
      label: _labelController.text,
      autoUpdate: _autoUpdate,
      autoUpdateDuration: interval != null && interval > 0
          ? Duration(minutes: interval)
          : current.autoUpdateDuration,
    );
    final profilesAction = ref.read(profilesActionProvider.notifier);
    final appLocalizations = context.appLocalizations;
    // 请求头变了也必须重新拉取，否则改动要等到下次自动更新才生效。
    final hasUpdate =
        current.url != profile.url ||
        current.ageSecretKey != profile.ageSecretKey ||
        current.userAgent != profile.userAgent ||
        !const DeepCollectionEquality().equals(
          current.customHeaders,
          profile.customHeaders,
        );
    if (_fileData != null) {
      if (profile.type == ProfileType.url && _autoUpdate) {
        final res = await dialogs.showMessage(
          title: appLocalizations.tip,
          message: TextSpan(text: appLocalizations.profileHasUpdate),
        );
        if (res == true) {
          profile = profile.copyWith(autoUpdate: false);
        }
      }
      final savedProfile = await globalState.safeRun(
        () => profile.saveFile(
          _fileData!,
          validate: (path, key) =>
              ref.read(coreHandlerProvider).validateProfile(path, key),
        ),
      );
      if (savedProfile == null) {
        return;
      }
      profilesAction.putProfile(savedProfile);
    } else if (!hasUpdate) {
      profilesAction.putProfile(profile);
    } else {
      unawaited(
        globalState.safeRun(() async {
          await Future.delayed(commonDuration);
          if (hasUpdate) {
            await profilesAction.updateProfile(profile);
          }
        }),
      );
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _setAutoUpdate(bool value) {
    if (_autoUpdate == value) return;
    setState(() {
      _autoUpdate = value;
    });
  }

  Future<void> _handleSaveEdit(BuildContext context, Uint8List data) async {
    final message = await globalState.safeRun<String>(() async {
      final message = await ref
          .read(profilesActionProvider.notifier)
          .validateConfigWithData(data);
      return message;
    }, silence: false);
    if (message?.isNotEmpty == true) {
      unawaited(
        dialogs.showAlert(
          title: currentAppLocalizations.tip,
          message: TextSpan(text: message),
        ),
      );
      return;
    }
    if (context.mounted) {
      Navigator.of(context).pop(data);
    }
  }

  Future<void> _editProfileFile() async {
    final title = widget.profile.label.takeFirstValid([
      widget.profile.id.toString(),
    ]);
    final editedData = _editedData;
    final editorPage = EditorPage(
      title: title,
      load: () async => editedData != null
          ? CodeForgeDocument.fromUtf8(editedData)
          : openEditorFile(
              await appPath.getProfilePath(widget.profile.id.toString()),
            ),
      onSave: (context, _, content) async {
        final data = await content.readBytes();
        if (context.mounted) {
          await _handleSaveEdit(context, data);
        }
      },
      onPop: (context, _, content) async {
        final res = await dialogs.showMessage(
          title: title,
          message: TextSpan(text: context.appLocalizations.hasCacheChange),
        );
        if (res != true || !context.mounted) {
          return true;
        }
        final data = await content.readBytes();
        if (context.mounted) {
          unawaited(_handleSaveEdit(context, data));
        }
        return false;
      },
    );
    final data = await BaseNavigator.push<Uint8List>(context, editorPage);
    if (data == null || !mounted) {
      return;
    }
    _editedData = data;
    setState(() {
      _fileData = data;
    });
    _fileInfoNotifier.value = _fileInfoNotifier.value?.copyWith(
      size: _fileData?.length ?? 0,
      lastModified: DateTime.now(),
    );
  }

  Future<void> _uploadProfileFile() async {
    final platformFile = await globalState.safeRun(picker.pickerFile);
    if (platformFile == null) return;
    final fileData = await platformFile.readBytes();
    if (!mounted) {
      return;
    }
    setState(() {
      _fileData = fileData;
    });
    _fileInfoNotifier.value = _fileInfoNotifier.value?.copyWith(
      size: _fileData?.length ?? 0,
      lastModified: DateTime.now(),
    );
  }

  Future<void> _handleBack() async {
    final appLocalizations = context.appLocalizations;
    final res = await dialogs.showMessage(
      title: appLocalizations.tip,
      message: TextSpan(text: appLocalizations.fileIsUpdate),
    );
    if (res == true) {
      unawaited(_handleConfirm());
    } else {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    _urlController.dispose();
    _ageSecretKeyController.dispose();
    _userAgentController.dispose();
    _customHeadersController.dispose();
    _fileInfoNotifier.dispose();
    _autoUpdateDurationController.dispose();
    super.dispose();
    _setupAction.autoApplyProfile();
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final isUrl = widget.profile.type == ProfileType.url;
    final issue = _attempted ? _issue(appLocalizations) : null;
    final sections = [
      generateSection(
        items: [
          _ProfileNameField(
            controller: _labelController,
            invalid: issue?.field == _ProfileField.label,
            onChanged: _handleChanged,
          ),
          if (isUrl)
            _ProfileUrlField(
              controller: _urlController,
              invalid: issue?.field == _ProfileField.url,
              onChanged: _handleChanged,
            ),
          _AgeSecretKeyField(controller: _ageSecretKeyController),
        ],
      ),
      if (isUrl)
        generateSection(
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
                invalid: issue?.field == _ProfileField.customHeaders,
                // 复用导入页的同一个控件，避免两处各写一份多行输入框后行为漂移。
                trailing: MultiLineHeaderField(
                  controller: _customHeadersController,
                  hintText: appLocalizations.customHeadersTip,
                  onChanged: _handleChanged,
                ),
              ),
            ],
          ],
        ),
      if (isUrl)
        generateSection(
          items: [
            FormRow(
              title: appLocalizations.autoUpdate,
              onPressed: () => _setAutoUpdate(!_autoUpdate),
              trailing: CommonSwitch(
                value: _autoUpdate,
                onChanged: _setAutoUpdate,
              ),
            ),
            if (_autoUpdate)
              _AutoUpdateIntervalField(
                controller: _autoUpdateDurationController,
                invalid: issue?.field == _ProfileField.autoUpdateInterval,
                onChanged: _handleChanged,
              ),
          ],
        ),
      generateSection(
        items: [
          _ProfileFileItem(
            fileInfoNotifier: _fileInfoNotifier,
            onEdit: _editProfileFile,
            onUpload: _uploadProfileFile,
          ),
        ],
      ),
    ];
    return FocusTraversalGroup(
      policy: PageTraversalPolicy(),
      child: PageFocusScope(
        child: CommonPopScope(
          onPop: _fileData == null
              ? null
              : (_) {
                  _handleBack();
                  return false;
                },
          child: CommonScaffold(
            title: appLocalizations.edit,
            confirmationAction: IconButtonData(
              glyph: AppGlyphs.check,
              onPressed: _handleConfirm,
              tooltip: appLocalizations.save,
            ),
            body: Builder(
              builder: (context) => ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
                  top: context.sectionsTopPadding,
                  bottom: context.bottomInset + 16,
                ),
                children: [
                  ErrorBanner(message: issue?.message),
                  ...sections,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String? validateProfileName(AppLocalizations appLocalizations, String? value) {
  if (value == null || value.isEmpty) {
    return appLocalizations.profileNameNullValidationDesc;
  }
  return null;
}

Future<void> renameProfile(
  BuildContext context,
  WidgetRef ref,
  Profile profile, {
  bool selectAll = false,
}) async {
  final appLocalizations = context.appLocalizations;
  final profilesAction = ref.read(profilesActionProvider.notifier);
  final label = await dialogs.showCommonDialog<String>(
    child: InputDialog(
      title: appLocalizations.rename,
      labelText: appLocalizations.name,
      value: profile.label,
      selectAll: selectAll,
      inputFormatters: TextInputLimits.limit(TextInputLimits.name),
      validator: (value) => validateProfileName(appLocalizations, value),
    ),
  );
  if (label == null || label == profile.label) {
    return;
  }
  profilesAction.putProfile(profile.copyWith(label: label));
}

class _ProfileNameField extends StatelessWidget {
  const _ProfileNameField({
    required this.controller,
    required this.invalid,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool invalid;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return FormRow(
      title: appLocalizations.name,
      invalid: invalid,
      trailing: FormRowTextField(
        controller: controller,
        hintText: appLocalizations.required,
        textInputAction: TextInputAction.next,
        inputFormatters: TextInputLimits.limit(TextInputLimits.name),
        onChanged: onChanged,
      ),
    );
  }
}

class _ProfileUrlField extends StatelessWidget {
  const _ProfileUrlField({
    required this.controller,
    required this.invalid,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool invalid;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return FormRow(
      title: appLocalizations.url,
      invalid: invalid,
      trailing: FormRowTextField(
        controller: controller,
        hintText: appLocalizations.required,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.next,
        autocorrect: false,
        inputFormatters: TextInputLimits.limit(TextInputLimits.url),
        onChanged: onChanged,
      ),
    );
  }
}

class _AgeSecretKeyField extends StatelessWidget {
  const _AgeSecretKeyField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return FormRow(
      title: appLocalizations.ageSecretKey,
      trailing: FormRowSecretTextField(
        controller: controller,
        hintText: appLocalizations.optional,
        textInputAction: TextInputAction.next,
      ),
    );
  }
}

class _AutoUpdateIntervalField extends StatelessWidget {
  const _AutoUpdateIntervalField({
    required this.controller,
    required this.invalid,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool invalid;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return FormRow(
      title: appLocalizations.autoUpdateInterval,
      invalid: invalid,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Flexible(
            child: FormRowTextField(
              controller: controller,
              hintText: appLocalizations.required,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              inputFormatters: TextInputLimits.digitsOnly(
                TextInputLimits.interval,
              ),
              onChanged: onChanged,
            ),
          ),
          Text(
            appLocalizations.minutes,
            style: AppTextStyle.subheadline.of(context),
          ),
        ],
      ),
    );
  }
}

class _ProfileFileItem extends StatelessWidget {
  const _ProfileFileItem({
    required this.fileInfoNotifier,
    required this.onEdit,
    required this.onUpload,
  });

  final ValueNotifier<FileInfo?> fileInfoNotifier;
  final VoidCallback onEdit;
  final VoidCallback onUpload;

  Widget _buildSubtitle(BuildContext context, FileInfo fileInfo) {
    final style = context.listCaptionStyle;
    final lastModified = fileInfo.lastModified;
    if (lastModified == null) {
      return Text(context.appLocalizations.unknown, style: style);
    }
    return LastUpdateTimeText(lastUpdateDate: lastModified, style: style);
  }

  List<CommonPopupMenuItem> _menuItems(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return [
      CommonPopupMenuItem(
        glyph: AppGlyphs.edit,
        label: appLocalizations.edit,
        onPressed: onEdit,
      ),
      CommonPopupMenuItem(
        glyph: AppGlyphs.upload,
        label: appLocalizations.upload,
        onPressed: onUpload,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return ValueListenableBuilder<FileInfo?>(
      valueListenable: fileInfoNotifier,
      builder: (context, fileInfo, _) {
        return FadeThroughBox(
          alignment: Alignment.centerLeft,
          child: fileInfo == null
              ? Container()
              : ContextMenuRegion(
                  menuItems: _menuItems(context),
                  child: DecorationListItem(
                    contentPadding: const EdgeInsets.only(left: 16),
                    title: Text(appLocalizations.profile),
                    subtitle: _buildSubtitle(context, fileInfo),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          fileInfo.size.traffic.show,
                          style: context.listCaptionStyle,
                        ),
                        const DisclosureIndicator(),
                      ],
                    ),
                    onPressed: onEdit,
                  ),
                ),
        );
      },
    );
  }
}
